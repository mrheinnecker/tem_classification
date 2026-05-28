# -*- coding: utf-8 -*-
"""
Created on Thu Jul  3 11:34:50 2025

@author: TEAM
"""

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
import random
from torchvision.transforms import functional as F
import os
from PIL import Image
import time
import numpy as np
t0= time.time()


print("SLURM_NTASKS:", os.environ.get("SLURM_NTASKS"))
print("SLURM_PROCID:", os.environ.get("SLURM_PROCID"))
print("CUDA_VISIBLE_DEVICES:", os.environ.get("CUDA_VISIBLE_DEVICES"))

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
        image1 = self.transform(img)
        image2 = self.transform(img)
        return image1,image2

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
class RandomDiscreteRotation:
    def __init__(self, angles=[0, 90, 180, 270]):
        self.angles = angles

    def __call__(self, img):
        angle = random.choice(self.angles)
        return F.rotate(img, angle)
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
image_paths=[]
for y in os.listdir(r"/g/schwab/GregoireMichelDeletie/slurm_outputs"):
    if y.startswith("cell_nb"):
        for x in os.listdir(os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext")):
            if x.endswith(".png"):
                image_paths.append(os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext",x))
#print(image_paths)

# Load pretrained DINOv2 ViT-B/14 from torch hub
dinov2 = torch.hub.load('facebookresearch/dinov2', 'dinov2_vitb14')

# Projection head for contrastive learning (input dim = 768)
projection_head = nn.Sequential(
    nn.Linear(768, 256),
    nn.ReLU(),
    nn.Linear(256, 128)
)
def cutmix_batch(images,ka,  alpha=1.0):
    batch_size = images.size(0)
    if alpha > 0:
        lam = np.random.beta(alpha, alpha)
    else:
        lam = 1.0

    # Generate shuffled indices
    index = torch.randperm(batch_size)

    # Get bounding box coordinates
    bbx1, bby1, bbx2, bby2 = rand_bbox(images.size(), lam)

    # Create new images with patches swapped
    mixed_images = images.clone()
    mixed_images[:, :, bby1:bby2, bbx1:bbx2] = images[index, :, bby1:bby2, bbx1:bbx2]

    return mixed_images, ka, ka[index],lam

def rand_bbox(size, lam):
    #print(size)
    W = size[2]
    H = size[3]
    cut_rat = np.sqrt(lam)

    cut_w = np.random.randint(int(np.ceil(max(1/2*cut_rat*W,lam*W))),int(np.floor(min(2*cut_rat*W,W)))+1)
    cut_h = round(lam*W*H/cut_w)
    cx=np.random.randint(W-cut_w+1)
    cy=np.random.randint(H-cut_h+1)

    bbx1 = np.clip(cx, 0, W)
    bby1 = np.clip(cy, 0, H)
    bbx2 = np.clip(cx + cut_w, 0, W)
    bby2 = np.clip(cy + cut_h, 0, H)

    return bbx1, bby1, bbx2, bby2


encoder = Dinov2EncoderWrapper(dinov2)

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
    checkpoint_path = r"/g/schwab/GregoireMichelDeletie/slurm_outputs/checkpointDataMix.pth"
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

def cutmix_loss(qm, ka, kb,lam, temp=0.1):
    return lam*nt_xent_loss(qm,ka,temp)+(1-lam)*nt_xent_loss(qm,kb,temp)


dataset = ContrastiveImageDataset(image_paths, contrastive_transforms)
train_sampler = torch.utils.data.distributed.DistributedSampler(dataset)
dataloader = DataLoader(dataset, sampler=train_sampler, batch_size=32, shuffle=False, num_workers=8)

to_pil =transforms.ToPILImage()

#model.encoder.dinov2.mask_token.requires_grad_(False)
epochs = 10
print("Start of training",time.time()-t0)
t1=time.time()
model.train()
for epoch in range(epochs):
    total_loss = 0
    train_sampler.set_epoch(epoch)
    #print(f"Number of parameters that do not recieve a gradient :")
    for x,ka in dataloader:
        gradiented=0
        ungradiented=0
        #print(x1.shape)
        qm,ka,kb,lam=cutmix_batch(x,ka)
        #qm = torch.stack([contrastive_transforms(to_pil(img)) for img in qm])
        #ka = torch.stack([contrastive_transforms(to_pil(img)) for img in ka])
        #kb = torch.stack([contrastive_transforms(to_pil(img)) for img in kb])

        qm, ka,kb = qm.cuda(), ka.cuda(),kb.cuda()
        #print(x1.shape)
        zm = model(qm)
        za = model(ka)
        zb = model(kb)
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

        loss = cutmix_loss(zm, za, zb,lam)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        total_loss += loss.item()
    print(f"Epoch {epoch+1}/{epochs} — Loss: {total_loss/len(dataloader):.4f} Time : {time.time()-t0:.2f}/{(time.time()-t1)*epochs/(epoch+1)+t1-t0:.2f} (estimation)")

cleanup_distributed()

torch.save({
    'model_state_dict': model.state_dict(),
    'optimizer_state_dict': optimizer.state_dict(),
}, r"/g/schwab/GregoireMichelDeletie/slurm_outputs/checkpointDataMixNoblack.pth")