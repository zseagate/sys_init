#!/bin/bash
# ==================================================
# 脚本名称：debian_ubuntu_post_install_optimize.sh
# 脚本版本：V1.1
# 更新日期：2026-05-15
# 支持系统：Debian 10+/Ubuntu 20.04+/MX Linux/Linux Mint/Lubuntu/Xubuntu/PeppermintOS/Zorin
# 支持架构：x86/i386(32位)、x86_64/amd64(64位)
# 功能描述：Debian系Linux系统安装后一站式优化脚本，包含驱动适配、中文环境配置、常用软件安装
# ==================================================

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 欢迎信息
clear
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}            Debian/Ubuntu系列Linux系统优化脚本 V1.1             ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""

# 权限检查
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[错误] 请使用sudo或以root用户运行此脚本${NC}"
    exit 1
fi

# 系统信息检测
echo -e "${YELLOW}[信息] 正在检测系统信息...${NC}"
ARCH=$(dpkg --print-architecture)
DISTRO=$(lsb_release -is 2>/dev/null || echo "Debian")
RELEASE=$(lsb_release -cs 2>/dev/null || grep "VERSION_CODENAME" /etc/os-release | cut -d'=' -f2)
KERNEL=$(uname -r)

echo "系统架构：$ARCH"
echo "发行版本：$DISTRO"
echo "版本代号：$RELEASE"
echo "内核版本：$KERNEL"
echo ""

# ==================================================
# 模块1：系统基础优化与自动更新
# ==================================================
echo -e "${YELLOW}[模块1/7] 系统基础优化与自动更新${NC}"

# 1.1 全量系统更新
echo -e "${YELLOW}[1.1] 正在执行系统全量更新...${NC}"
apt update -y
apt upgrade -y
apt dist-upgrade -y
echo -e "${GREEN}[完成] 系统软件包已更新至最新版本${NC}"

# 1.2 配置自动安全更新
echo -e "${YELLOW}[1.2] 正在配置自动安全更新...${NC}"
apt install -y unattended-upgrades apt-listchanges
echo -e "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\nAPT::Periodic::AutocleanInterval \"7\";" > /etc/apt/apt.conf.d/20auto-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades
echo -e "${GREEN}[完成] 自动安全更新已配置完成${NC}"

# 1.3 配置国内软件源
echo -e "${YELLOW}[1.3] 正在配置国内软件源...${NC}"
cp /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d)

if [ "$DISTRO" = "Ubuntu" ]; then
    cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu/ $RELEASE main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $RELEASE-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $RELEASE-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $RELEASE-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $RELEASE-backports main restricted universe multiverse
EOF
elif [ "$DISTRO" = "Debian" ]; then
    cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/debian/ $RELEASE main non-free contrib
deb http://mirrors.aliyun.com/debian-security $RELEASE-security main non-free contrib
deb http://mirrors.aliyun.com/debian/ $RELEASE-updates main non-free contrib
deb http://mirrors.aliyun.com/debian/ $RELEASE-backports main non-free contrib
EOF
fi

# 启用32位架构支持（64位系统）
if [ "$ARCH" = "amd64" ]; then
    dpkg --add-architecture i386
fi

apt update -y
echo -e "${GREEN}[完成] 国内软件源配置完成，原文件已备份为sources.list.backup${NC}"

# 1.4 安装基础系统工具
echo -e "${YELLOW}[1.4] 正在安装常用系统工具...${NC}"
apt install -y build-essential git curl wget vim htop net-tools dkms \
    linux-headers-$KERNEL apt-transport-https ca-certificates \
    software-properties-common p7zip-full unzip tar
echo -e "${GREEN}[完成] 基础系统工具安装完成${NC}"

# ==================================================
# 模块2：硬件驱动安装与适配
# ==================================================
echo -e "\n${YELLOW}[模块2/7] 硬件驱动安装与适配${NC}"

# 2.1 显卡驱动安装
echo -e "${YELLOW}[2.1] 显卡驱动检测与安装${NC}"
if lspci | grep -i "VGA compatible controller" | grep -i "nvidia" > /dev/null; then
    echo "检测到NVIDIA显卡，正在安装专有驱动..."
    add-apt-repository ppa:graphics-drivers/ppa -y
    apt update -y
    ubuntu-drivers autoinstall
    
    # 禁用nouveau开源驱动
    cat > /etc/modprobe.d/blacklist-nouveau.conf << EOF
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
    echo -e "${GREEN}[完成] NVIDIA显卡驱动安装完成，重启后生效${NC}"

elif lspci | grep -i "VGA compatible controller" | grep -E "(amd|ati)" > /dev/null; then
    echo "检测到AMD/ATI显卡，正在安装开源驱动..."
    apt install -y firmware-linux-nonfree firmware-amd-graphics mesa-utils vulkan-tools
    
    # 修复AMD Secure Display错误
    if grep -q "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&amdgpu.securedisplay=0 /' /etc/default/grub
        update-grub
    fi
    echo -e "${GREEN}[完成] AMD显卡驱动安装完成${NC}"

else
    echo "未检测到独立显卡，跳过显卡驱动安装"
fi

# 2.2 无线网卡驱动安装
echo -e "\n${YELLOW}[2.2] 无线网卡驱动检测与安装${NC}"
if lspci | grep -i "network controller" | grep -i "intel" > /dev/null; then
    echo "检测到Intel无线网卡，正在安装固件..."
    apt install -y firmware-iwlwifi
    echo -e "${GREEN}[完成] Intel无线网卡驱动安装完成${NC}"

elif lspci | grep -i "network controller" | grep -i "realtek" > /dev/null; then
    echo "检测到Realtek无线网卡，正在安装固件..."
    apt install -y firmware-realtek
    echo -e "${GREEN}[完成] Realtek无线网卡驱动安装完成${NC}"

elif lspci | grep -i "network controller" | grep -i "atheros" > /dev/null; then
    echo "检测到高通Atheros无线网卡，正在安装固件..."
    apt install -y firmware-atheros
    echo -e "${GREEN}[完成] 高通无线网卡驱动安装完成${NC}"

elif lspci | grep -i "network controller" | grep -i "broadcom" > /dev/null; then
    echo "检测到博通无线网卡，正在安装驱动..."
    apt install -y broadcom-sta-dkms
    modprobe -r b43 ssb wl bcma 2>/dev/null
    modprobe wl
    echo -e "${GREEN}[完成] 博通无线网卡驱动安装完成${NC}"

else
    echo "未检测到特殊无线网卡，跳过驱动安装"
fi

# 2.3 蓝牙驱动安装
echo -e "\n${YELLOW}[2.3] 蓝牙驱动检测与安装${NC}"
if lspci | grep -i "bluetooth" > /dev/null || lsusb | grep -i "bluetooth" > /dev/null; then
    echo "检测到蓝牙设备，正在安装蓝牙驱动和工具..."
    apt install -y bluez bluez-tools blueman pulseaudio-module-bluetooth
    
    # 启用蓝牙服务
    systemctl enable bluetooth
    systemctl start bluetooth
    
    # 配置自动启用蓝牙
    if [ -f /etc/bluetooth/main.conf ]; then
        sed -i 's/#AutoEnable=false/AutoEnable=true/' /etc/bluetooth/main.conf
    fi
    echo -e "${GREEN}[完成] 蓝牙驱动和服务安装完成${NC}"
else
    echo "未检测到蓝牙设备，跳过蓝牙驱动安装"
fi

# ==================================================
# 模块3：中文环境配置
# ==================================================
echo -e "\n${YELLOW}[模块3/7] 中文环境配置${NC}"

# 3.1 安装中文语言包
echo -e "${YELLOW}[3.1] 正在安装中文语言支持...${NC}"
apt install -y language-pack-zh-hans language-pack-gnome-zh-hans
locale-gen zh_CN.UTF-8
echo -e "${GREEN}[完成] 中文语言包安装完成${NC}"

# 3.2 安装中文字体
echo -e "${YELLOW}[3.2] 正在安装中文字体...${NC}"
apt install -y fonts-wqy-microhei fonts-wqy-zenhei xfonts-wqy fonts-noto-cjk

# 配置字体渲染优化
cat > /etc/fonts/local.conf << EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <match target="font">
        <edit name="antialias" mode="assign">
            <bool>true</bool>
        </edit>
        <edit name="hinting" mode="assign">
            <bool>true</bool>
        </edit>
        <edit name="hintstyle" mode="assign">
            <const>hintslight</const>
        </edit>
        <edit name="rgba" mode="assign">
            <const>rgb</const>
        </edit>
    </match>
</fontconfig>
EOF

fc-cache -fv
echo -e "${GREEN}[完成] 中文字体安装与配置完成${NC}"

# ==================================================
# 模块4：Fcitx5输入法安装（拼音+五笔）
# ==================================================
echo -e "\n${YELLOW}[模块4/7] Fcitx5输入法安装配置${NC}"

# 4.1 清理旧输入法框架
echo -e "${YELLOW}[4.1] 正在清理旧输入法框架...${NC}"
apt purge -y fcitx* ibus*
apt autoremove -y
rm -rf /etc/skel/.config/fcitx /etc/skel/.config/ibus 2>/dev/null
echo -e "${GREEN}[完成] 旧输入法框架清理完成${NC}"

# 4.2 安装Fcitx5组件
echo -e "${YELLOW}[4.2] 正在安装Fcitx5输入法...${NC}"
apt install -y fcitx5 fcitx5-chinese-addons fcitx5-configtool \
    fcitx5-frontend-gtk2 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
    fcitx5-frontend-qt5 fcitx5-material-color fcitx5-pinyin-moegirl \
    fcitx5-pinyin-zhwiki

# 4.3 配置全局环境变量
echo -e "${YELLOW}[4.3] 正在配置输入法环境变量...${NC}"
cat > /etc/profile.d/fcitx5.sh << EOF
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
export XMODIFIERS=@im=fcitx5
export SDL_IM_MODULE=fcitx5
export GLFW_IM_MODULE=fcitx5
EOF

# 设置为系统默认输入法
im-config -n fcitx5
echo -e "${GREEN}[完成] Fcitx5输入法安装完成，包含拼音和五笔输入方案${NC}"

# ==================================================
# 模块5：WPS Office安装
# ==================================================
echo -e "\n${YELLOW}[模块5/7] WPS Office安装配置${NC}"

echo -e "${YELLOW}[5.1] 正在下载WPS Office安装包...${NC}"
WPS_VERSION="11.1.0.11719"
WPS_URL="https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2019/11719/wps-office_${WPS_VERSION}_${ARCH}.deb"
wget -O /tmp/wps-office.deb "$WPS_URL" -q --show-progress

echo -e "${YELLOW}[5.2] 正在安装WPS Office...${NC}"
dpkg -i /tmp/wps-office.deb
apt --fix-broken install -y

# 5.3 修复WPS字体缺失问题
echo -e "${YELLOW}[5.3] 正在安装WPS缺失字体...${NC}"
mkdir -p /usr/share/fonts/wps-office
wget -O /tmp/wps-fonts.zip https://gitcode.com/Premium-Resources/a6802/raw/main/wps_symbol_fonts.zip -q
unzip /tmp/wps-fonts.zip -d /usr/share/fonts/wps-office > /dev/null
fc-cache -fv > /dev/null

# 5.4 修复WPS中文输入问题
echo -e "${YELLOW}[5.4] 正在修复WPS中文输入兼容性...${NC}"
sed -i '1a export XMODIFIERS="@im=fcitx5"\nexport QT_IM_MODULE="fcitx5"' /usr/bin/wps
sed -i '1a export XMODIFIERS="@im=fcitx5"\nexport QT_IM_MODULE="fcitx5"' /usr/bin/et
sed -i '1a export XMODIFIERS="@im=fcitx5"\nexport QT_IM_MODULE="fcitx5"' /usr/bin/wpp

rm -f /tmp/wps-office.deb /tmp/wps-fonts.zip
echo -e "${GREEN}[完成] WPS Office安装与配置完成${NC}"

# ==================================================
# 模块6：星火应用商店安装
# ==================================================
echo -e "\n${YELLOW}[模块6/7] 星火应用商店安装${NC}"

if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "arm64" ]; then
    echo -e "${YELLOW}[提示] 星火应用商店暂不支持$ARCH架构，跳过安装${NC}"
else
    echo -e "${YELLOW}[6.1] 正在添加星火应用商店软件源...${NC}"
    curl -fsSL https://gitcode.com/spark-store-project/spark-store/raw/main/tool/install-repo.sh | bash
    apt update -y

    echo -e "${YELLOW}[6.2] 正在安装星火应用商店...${NC}"
    apt install -y spark-store

    # 修复Ubuntu 20.04 DTK依赖问题
    if [ "$RELEASE" = "focal" ]; then
        echo -e "${YELLOW}[提示] 检测到Ubuntu 20.04，正在修复依赖问题...${NC}"
        wget -O /tmp/spark-deps.zip https://gitee.com/spark-store-project/spark-store-dependencies/releases/download/1.0/spark-store-dependencies-kylin.zip -q
        unzip /tmp/spark-deps.zip -d /tmp/spark-deps > /dev/null
        tar xvf /tmp/spark-deps/解压我.tar -C /tmp/spark-deps > /dev/null
        apt install -y /tmp/spark-deps/all-depends/Debian10-or-ubuntu-20.04/*.deb > /dev/null
        rm -rf /tmp/spark-deps /tmp/spark-deps.zip
        apt install -y spark-store
    fi
    echo -e "${GREEN}[完成] 星火应用商店安装完成${NC}"
fi

# ==================================================
# 模块7：系统清理与最终优化
# ==================================================
echo -e "\n${YELLOW}[模块7/7] 系统清理与最终优化${NC}"

# 7.1 系统缓存清理
echo -e "${YELLOW}[7.1] 正在清理系统缓存...${NC}"
apt autoremove -y
apt autoclean
apt clean
rm -rf /tmp/*
echo -e "${GREEN}[完成] 系统缓存清理完成${NC}"

# 7.2 系统参数优化
echo -e "${YELLOW}[7.2] 正在优化系统参数...${NC}"
echo "vm.swappiness=10" >> /etc/sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
sysctl -p > /dev/null
echo -e "${GREEN}[完成] 系统参数优化完成${NC}"

# ==================================================
# 执行完成
# ==================================================
echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}                     所有优化操作已执行完成                     ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "${YELLOW}请重启系统以应用所有配置，重启后可进行以下验证：${NC}"
echo "1. 执行 nvidia-smi 检查NVIDIA显卡驱动状态"
echo "2. 运行 fcitx5-configtool 配置输入法（添加五笔/拼音）"
echo "3. 在应用菜单中找到WPS Office和星火应用商店"
echo "4. 蓝牙设备可在系统设置或blueman管理器中管理"
echo ""
echo -e "${GREEN}感谢使用本脚本，祝你使用愉快！${NC}"
echo ""
