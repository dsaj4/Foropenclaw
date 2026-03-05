# 阿里云服务器 + GitHub 网站部署指南

> **适用场景**：将静态网站（HTML/CSS/JS）部署到阿里云服务器，并通过GitHub进行版本管理  
> **目标读者**：Visiontree前端开发团队（xc, mwb）  
> **最后更新**：2026年3月5日

---

## 目录

1. [部署架构概览](#1-部署架构概览)
2. [准备工作](#2-准备工作)
3. [阿里云服务器配置](#3-阿里云服务器配置)
4. [GitHub仓库设置](#4-github仓库设置)
5. [网站部署流程](#5-网站部署流程)
6. [域名配置（可选）](#6-域名配置可选)
7. [自动化部署（进阶）](#7-自动化部署进阶)
8. [常见问题排查](#8-常见问题排查)

---

## 1. 部署架构概览

```
用户访问流程：
用户浏览器 → 域名DNS解析 → 阿里云服务器(ECS) → Nginx → 静态网站文件
                                      ↑
                                      │
                              GitHub仓库(版本管理)
                                      │
                              开发者本地开发
```

**核心组件**：
- **阿里云ECS**：云服务器，运行网站
- **Nginx**：Web服务器，处理HTTP请求
- **GitHub**：代码版本管理和备份
- **域名**（可选）：用户友好的访问地址

---

## 2. 准备工作

### 2.1 所需资源清单

| 资源 | 用途 | 预估费用 |
|------|------|---------|
| 阿里云ECS（1核2G） | 运行网站 | ~100元/月 |
| 域名（.com/.cn） | 用户访问 | ~50-100元/年 |
| GitHub账号 | 代码管理 | 免费 |

### 2.2 本地环境准备

**必需工具**：
```bash
# 检查是否已安装
git --version        # Git版本控制
ssh -V              # SSH远程连接
scp --version       # 文件传输（可选）
```

**如未安装**：
- **Windows**：安装 [Git for Windows](https://git-scm.com/download/win)
- **Mac**：`brew install git`
- **Linux**：`sudo apt-get install git`

---

## 3. 阿里云服务器配置

### 3.1 购买和初始化ECS

**步骤1：购买ECS实例**
1. 登录 [阿里云控制台](https://ecs.console.aliyun.com/)
2. 选择「创建实例」
3. 配置选择：
   - **地域**：选择离用户最近的（如华东1-杭州）
   - **实例规格**：1核2G（入门配置）
   - **镜像**：CentOS 7.9 或 Ubuntu 20.04
   - **带宽**：1-5Mbps（根据访问量调整）
4. 设置登录密码或SSH密钥
5. 完成购买

**步骤2：配置安全组（开放端口）**
```
安全组规则：
- 入方向：
  - 端口 22 (SSH)      源：0.0.0.0/0  或 你的IP
  - 端口 80 (HTTP)     源：0.0.0.0/0
  - 端口 443 (HTTPS)   源：0.0.0.0/0
```

**步骤3：获取服务器IP**
- 在ECS控制台查看「公网IP地址」
- 记录备用，如：`47.123.45.67`

### 3.2 连接服务器并安装Nginx

**连接服务器**：
```bash
# 使用SSH连接（将IP替换为你的服务器IP）
ssh root@47.123.45.67

# 输入购买时设置的密码
```

**安装Nginx**（CentOS）：
```bash
# 更新系统
yum update -y

# 安装Nginx
yum install -y nginx

# 启动Nginx
systemctl start nginx
systemctl enable nginx

# 检查状态
systemctl status nginx
```

**安装Nginx**（Ubuntu）：
```bash
# 更新系统
apt-get update

# 安装Nginx
apt-get install -y nginx

# 启动Nginx
systemctl start nginx
systemctl enable nginx

# 检查状态
systemctl status nginx
```

**验证安装**：
- 浏览器访问：`http://47.123.45.67`
- 应看到Nginx默认欢迎页面

### 3.3 配置网站目录

```bash
# 创建网站根目录
mkdir -p /var/www/visiontree

# 设置权限
chown -R nginx:nginx /var/www/visiontree
chmod -R 755 /var/www/visiontree

# 备份默认配置
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
```

**编辑Nginx配置**：
```bash
# 编辑配置文件
vim /etc/nginx/conf.d/visiontree.conf
```

**添加以下内容**：
```nginx
server {
    listen 80;
    server_name _;  # 暂时接受所有域名，后续可改为你的域名
    
    root /var/www/visiontree;
    index index.html index.htm;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # 静态文件缓存（可选）
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    # Gzip压缩（提升加载速度）
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
}
```

**检查配置并重启**：
```bash
# 检查配置语法
nginx -t

# 重启Nginx
systemctl restart nginx
```

---

## 4. GitHub仓库设置

### 4.1 创建GitHub仓库

**步骤1：在GitHub创建新仓库**
1. 登录 [GitHub](https://github.com)
2. 点击右上角「+」→「New repository」
3. 填写信息：
   - Repository name: `visiontree-website`
   - Description: Visiontree官方网站
   - Visibility: Public（或Private）
   - 勾选「Add a README file」
4. 点击「Create repository」

**步骤2：本地初始化并推送**
```bash
# 进入网站项目目录
cd /path/to/visiontree_website

# 初始化Git仓库
git init

# 添加所有文件
git add .

# 提交
git commit -m "Initial commit: Visiontree website v1.0"

# 关联远程仓库（替换为你的仓库地址）
git remote add origin https://github.com/yourusername/visiontree-website.git

# 推送
git push -u origin master
```

### 4.2 配置GitHub Token（用于自动化部署）

**生成Token**：
1. GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic)
3. 勾选权限：`repo`（完整仓库访问）
4. 生成并复制Token（只显示一次）

---

## 5. 网站部署流程

### 5.1 手动部署（首次）

**从本地部署到阿里云**：
```bash
# 方法1：使用scp命令
scp -r /path/to/visiontree_website/* root@47.123.45.67:/var/www/visiontree/

# 方法2：使用rsync（推荐，支持增量同步）
rsync -avz --delete /path/to/visiontree_website/ root@47.123.45.67:/var/www/visiontree/
```

**验证部署**：
- 浏览器访问：`http://47.123.45.67`
- 应看到你的网站

### 5.2 后续更新部署

**更新流程**：
```bash
# 1. 本地修改代码
# ...

# 2. 提交到GitHub
git add .
git commit -m "Update: xxx feature"
git push origin master

# 3. 部署到服务器
rsync -avz --delete /path/to/visiontree_website/ root@47.123.45.67:/var/www/visiontree/
```

---

## 6. 域名配置（可选）

### 6.1 购买域名

**阿里云域名购买**：
1. 登录 [阿里云域名控制台](https://domain.console.aliyun.com/)
2. 搜索并购买域名（如 `visiontree.ai`）
3. 完成实名认证

### 6.2 配置DNS解析

**添加解析记录**：
```
记录类型：A
主机记录：@      # 主域名
解析线路：默认
记录值：47.123.45.67   # 你的服务器IP
TTL：10分钟
```

### 6.3 配置Nginx支持域名

```bash
# 编辑配置
vim /etc/nginx/conf.d/visiontree.conf
```

**修改为**：
```nginx
server {
    listen 80;
    server_name visiontree.ai www.visiontree.ai;  # 你的域名
    
    root /var/www/visiontree;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**重启Nginx**：
```bash
nginx -t
systemctl restart nginx
```

### 6.4 配置HTTPS（SSL证书）

**使用Certbot免费证书**：
```bash
# 安装Certbot
yum install -y certbot python2-certbot-nginx

# 申请证书
certbot --nginx -d visiontree.ai -d www.visiontree.ai

# 按提示操作，选择重定向HTTP到HTTPS

# 自动续期测试
certbot renew --dry-run
```

---

## 7. 自动化部署（进阶）

### 7.1 使用GitHub Actions自动部署

**创建GitHub Actions工作流**：
```bash
# 在本地项目创建目录
mkdir -p .github/workflows

# 创建部署配置文件
touch .github/workflows/deploy.yml
```

**编辑 `.github/workflows/deploy.yml`**：
```yaml
name: Deploy to Aliyun

on:
  push:
    branches: [ master ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Deploy to Aliyun ECS
      uses: appleboy/scp-action@master
      with:
        host: ${{ secrets.HOST }}
        username: root
        password: ${{ secrets.PASSWORD }}
        source: "."
        target: "/var/www/visiontree"
        strip_components: 0
```

**配置GitHub Secrets**：
1. GitHub仓库 → Settings → Secrets and variables → Actions
2. 添加以下secrets：
   - `HOST`: 你的服务器IP（如 47.123.45.67）
   - `PASSWORD`: 服务器root密码

**测试自动部署**：
```bash
# 本地修改并推送
git add .
git commit -m "Test auto deploy"
git push origin master

# 查看GitHub Actions运行状态
# GitHub仓库 → Actions 标签页
```

### 7.2 使用Webhook实现自动拉取（服务器端）

**服务器端配置自动更新脚本**：
```bash
# 创建更新脚本
vim /opt/update_website.sh
```

**添加内容**：
```bash
#!/bin/bash
cd /var/www/visiontree
git pull origin master
systemctl restart nginx
echo "Updated at $(date)" >> /var/log/website_update.log
```

```bash
# 添加执行权限
chmod +x /opt/update_website.sh

# 配置定时任务（每5分钟检查更新）
crontab -e
# 添加：
*/5 * * * * /opt/update_website.sh
```

---

## 8. 常见问题排查

### 8.1 无法访问网站

**检查清单**：
```bash
# 1. 检查Nginx运行状态
systemctl status nginx

# 2. 检查端口监听
netstat -tlnp | grep nginx

# 3. 检查防火墙
firewall-cmd --list-all
# 或
iptables -L -n

# 4. 检查安全组（阿里云控制台）
# 确保80/443端口已开放

# 5. 查看Nginx错误日志
tail -f /var/log/nginx/error.log
```

### 8.2 403 Forbidden错误

**解决方案**：
```bash
# 检查文件权限
ls -la /var/www/visiontree

# 修复权限
chown -R nginx:nginx /var/www/visiontree
chmod -R 755 /var/www/visiontree

# 检查SELinux（CentOS）
getenforce
setenforce 0  # 临时关闭
# 或
chcon -Rt httpd_sys_content_t /var/www/visiontree
```

### 8.3 部署后页面不更新

**原因和解决**：
```bash
# 浏览器缓存
# 解决方案：Ctrl+F5 强制刷新

# Nginx缓存
systemctl restart nginx

# CDN缓存（如使用了阿里云CDN）
# 登录阿里云CDN控制台刷新缓存
```

### 8.4 Git推送失败

**常见错误和解决**：
```bash
# 错误：Permission denied
# 解决：检查服务器密码或SSH密钥

# 错误：Could not resolve host
# 解决：检查网络连接
ping github.com

# 错误：Updates were rejected
# 解决：先拉取再推送
git pull origin master
git push origin master
```

---

## 附录

### A. 常用命令速查

```bash
# Nginx管理
systemctl start nginx      # 启动
systemctl stop nginx       # 停止
systemctl restart nginx    # 重启
systemctl reload nginx     # 重载配置
nginx -t                   # 检查配置

# 文件部署
scp -r local/ root@ip:/remote/           # 上传
rsync -avz local/ root@ip:/remote/       # 同步

# Git操作
git add .                  # 添加文件
git commit -m "msg"        # 提交
git push origin master     # 推送
git pull origin master     # 拉取
```

### B. 推荐工具

| 工具 | 用途 | 链接 |
|------|------|------|
| FileZilla | SFTP文件传输 | https://filezilla-project.org |
| Termius | SSH客户端 | https://termius.com |
| Postman | API测试 | https://postman.com |

---

*本指南随部署实践持续更新，如有问题请联系开发团队。*
