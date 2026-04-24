# -*- coding: utf-8 -*-
"""
Created on Wed Jul 16 10:55:48 2025

@author: TEAM
"""

import torch
import torch.nn as nn
from torch.nn.parallel import DistributedDataParallel as DDP
import torch.optim as optim
import torchvision
import torchvision.transforms as transforms
from torch.utils.data import Dataset,DataLoader
import torch.distributed as dist
import os
from PIL import Image
import numpy as np
import math
import time
import copy
t0= time.time()

LOCAL=4

def setup_distributed():
    rank = int(os.environ.get('SLURM_PROCID', 0))
    world_size = int(os.environ.get('SLURM_NTASKS', 1))
    
    torch.cuda.set_device(0)
    
    
    # Parse MASTER_ADDR from node list

    os.environ['RANK'] = str(rank)
    os.environ['WORLD_SIZE'] = str(world_size)

    dist.init_process_group(backend='nccl', init_method='env://', rank=rank, world_size=world_size)

def cleanup_distributed():
    dist.destroy_process_group()


class ContrastiveImageDataset(Dataset):
    def __init__(self, image_paths, transformG,transformL):
        self.image_paths = image_paths
        self.transformG = transformG
        self.transformL = transformL
        self.globalTrans = 2
        self.localTrans = LOCAL

    def __len__(self):
        return len(self.image_paths)

    def __getitem__(self, idx):
        path = self.image_paths[idx]
        img = Image.open(path).convert('RGB')
        # Two random augmentations of the same image for contrastive learning
        augs=[]
        for i in range(self.globalTrans):
            augs.append(self.transformG(img))
        for i in range(self.localTrans):
            augs.append(self.transformL(img))
        return augs,path

class DinoFineTuneModel(nn.Module):
    def __init__(self, encoder, projector):
        super().__init__()
        self.encoder = encoder
        self.projector = projector
    
    def forward(self, x):
        features = self.encoder(x)
        #print(f"features type: {type(features)}; requires_grad: {features.requires_grad}")
        return self.projector(features)

class Dinov2EncoderWrapper(nn.Module):
    def __init__(self, dinov2_model):
        super().__init__()
        self.dinov2 = dinov2_model

    def forward(self, x):
        out = self.dinov2(x)
        return out
    
class TeacherCentering:
    def __init__(self, dim, momentum=0.9):
        self.center = torch.zeros(1, dim).cuda()
        self.momentum = momentum

    def update(self, batch_logits):
        batch_mean = batch_logits.mean(dim=(0,1), keepdim=False)
        #print(batch_mean.shape)
        self.center = self.center * self.momentum + batch_mean * (1 - self.momentum)
        #print(f"Update : /center: {self.center}")

    def apply(self, logits):
        #print(f"Apply /logits :{logits}\n /center: {self.center}")
        #print(self.center)
        return logits - self.center

def get_cosine_schedule_with_warmup(optimizer, warmup_steps, total_steps, base_lr, min_lr=0):
    def lr_lambda(current_step):
        if current_step < warmup_steps:
            # Linear warmup
            return float(current_step) / float(max(1, warmup_steps))
        # Cosine decay
        progress = float(current_step - warmup_steps) / float(max(1, total_steps - warmup_steps))
        cosine_decay = 0.5 * (1 + math.cos(math.pi * progress))
        return max(min_lr / base_lr, cosine_decay)

    scheduler = torch.optim.lr_scheduler.LambdaLR(optimizer, lr_lambda)
    return scheduler

def nt_xent_loss(z1, z2, temperature=0.1):
    z1 = nn.functional.normalize(z1, dim=1)
    z2 = nn.functional.normalize(z2, dim=1)
    representations = torch.cat([z1, z2], dim=0)
    similarity_matrix = torch.matmul(representations, representations.T)

    batch_size = z1.shape[0]
    #labels = torch.arange(batch_size).cuda()
    #labels = torch.cat([labels, labels], dim=0)

    mask = torch.eye(2 * batch_size, dtype=torch.bool).cuda()
    similarity_matrix = similarity_matrix[~mask].view(2 * batch_size, -1)

    positives = torch.exp(torch.sum(z1 * z2, dim=-1) / temperature)
    positives = torch.cat([positives, positives], dim=0)

    denominator = torch.sum(torch.exp(similarity_matrix / temperature), dim=1)
    loss = -torch.log(positives / denominator).mean()
    return loss

def get_model():
    encoder = Dinov2EncoderWrapper(dinov2)
    
    #for param in encoder.parameters():
        #param.requires_grad = False
    
    model = DinoFineTuneModel(encoder, projection_head)
    model = model.cuda()
    setup_distributed()
    
    
    model = nn.parallel.DistributedDataParallel(
        model,
        device_ids=[torch.cuda.current_device()],
        find_unused_parameters=True,
    )
    optimizer = optim.Adam(model.parameters(), lr=1e-4)
    
    resume=True
    if resume:
        checkpoint_path = r"/g/schwab/GregoireMichelDeletie/slurm_outputs/teacherStudent2.pth"
        state_dict = torch.load(checkpoint_path, map_location='cuda')
        model.load_state_dict(state_dict['model_state_dict'])
        optimizer.load_state_dict(state_dict['optimizer_state_dict'])
        for param_group in optimizer.param_groups:
            param_group['lr'] /= 3
    model.train()
    return model,optimizer

def distillation_loss(student_out, teacher_out, temperature=0.1):
    student_out = nn.functional.normalize(student_out, dim=1)
    teacher_out = nn.functional.normalize(teacher_out, dim=1)
    # Normalize
    student_out = nn.functional.log_softmax(student_out / temperature, dim=-1)
    teacher_out = nn.functional.softmax(teacher_out / temperature, dim=-1)
    loss = nn.functional.kl_div(student_out, teacher_out, reduction='batchmean')
    var = student_out.var(dim=0) 
    var_loss = torch.mean(nn.functional.relu(1e-2 - var))
    return loss+ 0.1 * var_loss



def variance_loss(outputs, min_var=5e-3):
    z_stack = torch.stack(outputs, dim=0) 
    var = z_stack.var(dim=0).mean() 
    return torch.relu(min_var - var)

def distillation_loss_list(student_outputs, teacher_outputs,Ttemp=0.04, Stemp=0.1 ):
    total_loss = 0.0
    n_loss_terms = 0
    teacher_probs = [
        nn.functional.softmax((t_out) / Ttemp, dim=-1).detach()
        for t_out in teacher_outputs
    ]
    
    e = entropy(teacher_probs[0])

    student_log_probs = [
        nn.functional.log_softmax(s_out / Stemp, dim=-1)
        for s_out in student_outputs
    ]
    for t_idx, t_prob in enumerate(teacher_probs):
        for s_idx, s_log_prob in enumerate(student_log_probs):
            if t_idx == s_idx:
                continue

            loss = torch.sum(-t_prob * s_log_prob, dim=-1).mean()
            total_loss += loss
            n_loss_terms += 1

    return total_loss / n_loss_terms,e
def entropy(probs):
    return -(probs * torch.log(probs + 1e-8)).sum(dim=-1).mean().item()
def unfreeze_last_n_blocks(model, n):
    for i in range(-n, 0):  # last n blocks
        for param in model.module.encoder.dinov2.blocks[i].parameters():
            param.requires_grad = True

if __name__ == "__main__":
    tranforms= transforms.Compose([
        transforms.RandomHorizontalFlip(),
        transforms.RandomChoice([
        transforms.RandomRotation([0, 0]),    
        transforms.RandomRotation([90, 90]),  
        transforms.RandomRotation([180, 180]),
        transforms.RandomRotation([270, 270]) 
        ]),
        transforms.RandomAffine(degrees=10,scale=(1,1.24),translate=(0.05, 0.05)),
        transforms.ColorJitter(brightness=0.4, contrast=0.4),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225]),
    ])
    global_transforms = transforms.Compose([
        transforms.RandomResizedCrop(224, scale=(0.8, 1.0)),
        tranforms
    ])
    local_transforms = transforms.Compose([
        transforms.RandomResizedCrop(98, scale=(0.2, 0.8)),
        tranforms
    ])
    #print("SLURM_NTASKS:", os.environ.get("SLURM_NTASKS"))
    #print("SLURM_PROCID:", os.environ.get("SLURM_PROCID"))
    #print("CUDA_VISIBLE_DEVICES:", os.environ.get("CUDA_VISIBLE_DEVICES"))
    image_paths=[]
    for y in os.listdir(r"/g/schwab/GregoireMichelDeletie/slurm_outputs"):
        if y.startswith("cell_nb"):
            for x in os.listdir(os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext")):
                if x.endswith(".png"):
                    image_paths.append(os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext",x))
    #print(image_paths)
    
    # Load pretrained DINOv2 ViT-B/14 from torch hub
    dinov2 = torch.hub.load('facebookresearch/dinov2', 'dinov2_vits14')
    
    # Projection head for contrastive learning (input dim = 768)
    projection_head = nn.Sequential(
        nn.Linear(384, 128),
        nn.ReLU(),
        nn.Linear(128, 64)
    )
    
    epochs = 20
    momentum=0.998

    
    student,optimizer =get_model()
    teacher = copy.deepcopy(student)
    #for p in teacher.parameters():
    #    p.requires_grad = False 
    center_op = TeacherCentering(dim=64)
    
    dataset = ContrastiveImageDataset(image_paths,global_transforms,local_transforms)
    train_sampler = torch.utils.data.distributed.DistributedSampler(dataset)
    dataloader = DataLoader(dataset, sampler=train_sampler, batch_size=64, shuffle=False, num_workers=8)
    
    
    steps_per_epoch = math.ceil(len(dataloader.dataset) / dataloader.batch_size)
    nb_steps = steps_per_epoch*epochs
    scheduler = get_cosine_schedule_with_warmup(optimizer, nb_steps*0.05, nb_steps, 1e-4, 2e-7)
    

    #model.encoder.dinov2.mask_token.requires_grad_(False)
    print("Start of training",time.time()-t0)
    t1=time.time()
    started=False
    for epoch in range(epochs):
        total_loss = 0
        train_sampler.set_epoch(epoch)
        #print(f"Number of parameters that do not recieve a gradient :")
        maxdepth=len(student.module.encoder.dinov2.blocks)
        #unfreeze_last_n_blocks(student, min(maxdepth,epoch))
        z1means,z2means=[],[]
        
        for augs,x1_paths in dataloader:
            if not started:
                started=True
                print("let's go")
            #print(x1.shape)
            z1 = [student(v.cuda()) for v in augs]
            with torch.no_grad():
                z2 = [teacher(v.cuda()) for v in augs[:-LOCAL]]
                z2p = [center_op.apply(e) for e in z2]
            #print(f"{ungradiented}", end =", ")
            #print(z1.shape)
            z1_stack = torch.stack(z1, dim=0) 
            variance_per_dim = z1_stack.var(dim=0)  # shape: [embedding_dim]
            mean_variance = variance_per_dim.mean().item()  # scalar
            z1means.append(mean_variance)
            z2_stack = torch.stack(z2, dim=0) 
            variance_per_dim = z2_stack.var(dim=0)  # shape: [embedding_dim]
            mean_variance = variance_per_dim.mean().item()  # scalar
            z2means.append(mean_variance)
            
            loss,enthropy = distillation_loss_list(z1, z2p) 
            #loss+=+ variance_loss(z1)*50000
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            scheduler.step()
            center_op.update(torch.stack([e.detach() for e in z2]))
            
            with torch.no_grad():
                for param_s, param_t in zip(student.parameters(), teacher.parameters()):
                    param_t.data = momentum * param_t.data + (1 - momentum) * param_s.data
            total_loss += loss.item()
        print(f"Epoch {epoch+1}/{epochs} — Loss: {total_loss/len(dataloader):.4f}   Variance (S,T) :{sum(z1means)/len(z1means):.6f}, {sum(z2means)/len(z2means):.6f}   Enthropy :{enthropy:.6f}   Time : {time.time()-t0:.2f}/{(time.time()-t1)*epochs/(epoch+1)+t1-t0:.2f} (estimation)")
    
    cleanup_distributed()
    destination = r"/g/schwab/GregoireMichelDeletie/slurm_outputs/teacherStudent2.pth"
    torch.save({
        'model_state_dict': student.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
    }, destination)
    print("Checkpoint saves at : ",destination)