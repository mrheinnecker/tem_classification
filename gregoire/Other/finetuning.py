# -*- coding: utf-8 -*-
"""
Created on Fri Jun 27 10:16:48 2025

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
import time
t0= time.time()



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
    def __init__(self, image_paths, transform):
        self.image_paths = image_paths
        self.transform = transform

    def __len__(self):
        return len(self.image_paths)

    def __getitem__(self, idx):
        path = self.image_paths[idx]
        img = Image.open(path).convert('RGB')
        # Two random augmentations of the same image for contrastive learning
        img1 = self.transform(img)
        img2 = self.transform(img)
        return img1, img2,path

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

if __name__ == "__main__":
    contrastive_transforms = transforms.Compose([
        transforms.RandomResizedCrop(224, scale=(0.8, 1.0)),  # typical for SimCLR/DINO
        transforms.RandomHorizontalFlip(),
        transforms.RandomChoice([
        transforms.RandomRotation([0, 0]),    # 0 degrees (no rotation)
        transforms.RandomRotation([90, 90]),  # 90 degrees
        transforms.RandomRotation([180, 180]),# 180 degrees
        transforms.RandomRotation([270, 270]) # 270 degrees
        ]),
        transforms.RandomAffine(degrees=10,scale=(1.24,1.3),translate=(0.05, 0.05)),
        transforms.ColorJitter(brightness=0.4, contrast=0.4),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406],
                             std=[0.229, 0.224, 0.225]),
    ])
    print("SLURM_NTASKS:", os.environ.get("SLURM_NTASKS"))
    print("SLURM_PROCID:", os.environ.get("SLURM_PROCID"))
    print("CUDA_VISIBLE_DEVICES:", os.environ.get("CUDA_VISIBLE_DEVICES"))
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
    
    
    
    
    encoder = Dinov2EncoderWrapper(dinov2)
    
    for param in encoder.parameters():
        param.requires_grad = False
    
    model = DinoFineTuneModel(encoder, projection_head)
    model = model.cuda()
    setup_distributed()
    
    
    model = nn.parallel.DistributedDataParallel(
        model,
        device_ids=[torch.cuda.current_device()],
        find_unused_parameters=True,
    )
    optimizer = optim.Adam(model.parameters(), lr=2e-4)
    
    resume=False
    if resume:
        checkpoint_path = r"/g/schwab/GregoireMichelDeletie/slurm_outputs/checkpoint.pth"
        state_dict = torch.load(checkpoint_path, map_location='cuda')
        model.load_state_dict(state_dict['model_state_dict'])
        optimizer.load_state_dict(state_dict['optimizer_state_dict'])
        for param_group in optimizer.param_groups:
            param_group['lr'] /= 3
    
    
    
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
    
    
    
    dataset = ContrastiveImageDataset(image_paths, contrastive_transforms)
    train_sampler = torch.utils.data.distributed.DistributedSampler(dataset)
    dataloader = DataLoader(dataset, sampler=train_sampler, batch_size=32, shuffle=False, num_workers=8)
    print(model.module.encoder.dinov2.blocks)
    
    #model.encoder.dinov2.mask_token.requires_grad_(False)
    epochs = 5
    print("Start of training",time.time()-t0)
    model.train()
    t1=time.time()
    
    def unfreeze_last_n_blocks(model, n):
        for i in range(-n, 0):  # last n blocks
            for param in model.module.encoder.dinov2.blocks[i].parameters():
                param.requires_grad = True
    
    for epoch in range(epochs):
        total_loss = 0
        train_sampler.set_epoch(epoch)
        #print(f"Number of parameters that do not recieve a gradient :")
        maxdepth=len(model.module.encoder.dinov2.blocks)
        unfreeze_last_n_blocks(model, min(maxdepth,epoch))
        for x1, x2,x1_paths in dataloader:
            gradiented=0
            ungradiented=0
            #print(x1.shape)
            x1, x2 = x1.cuda(), x2.cuda()
            #print(x1.shape)
            z1 = model(x1)
            z2 = model(x2)
            for name, param in model.named_parameters():
                if param.requires_grad and (param.grad is not None):
                    gradiented+=1
                elif param.requires_grad :
                    ungradiented+=1
            #print(f"{ungradiented}", end =", ")
            if gradiented==0:
                #print("No grads for batch containing images:")
                #print("x1 images:", x1_paths)
                pass
            #print(z1.shape)
    
            loss = nt_xent_loss(z1, z2)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
    
            total_loss += loss.item()
        print(f"Epoch {epoch+1}/{epochs} — Loss: {total_loss/len(dataloader):.4f} Time : {time.time()-t0:.2f}/{(time.time()-t1)*epochs/(epoch+1)+t1-t0:.2f} (estimation)")
    
    cleanup_distributed()
    destination = r"/g/schwab/GregoireMichelDeletie/slurm_outputs/smallCheckpoint.pth"
    torch.save({
        'model_state_dict': model.state_dict(),
        'optimizer_state_dict': optimizer.state_dict(),
    }, destination)
    print("Checpoint saves at : ",destination)