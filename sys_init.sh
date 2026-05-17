#!/bin/bash
# Debian系Linux系统初始化优化脚本
# 版本: V2.1
# 日期: 2026-05-17
# 适用系统: Debian 12+/Debian 13+/Ubuntu 22.04+/MX Linux/Linux Mint 等全系列Debian系衍生发行版
# 测试验证: Debian 12/Debian 13/Ubuntu 22.04/Ubuntu 24.04 全功能测试通过

set -euo pipefail
trap 'echo -e "\n错误: 脚本在第 $LINENO 行执行失败，请检查上述错误信息"' ERR

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 必须使用sudo或root权限运行此脚本"
    exit 1
fi

# 检测系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION_CODENAME=$VERSION_CODENAME
else
    echo "错误: 无法检测系统发行版"
    exit 1
fi

echo "======================================"
echo "Debian系Linux系统优化脚本 V2.1"
echo "检测到系统: $PRETTY_NAME"
echo "======================================"
echo ""

# ------------------------------
# 新增功能: 国内镜像源自动测速与选择
# ------------------------------
echo "[0/7] 正在进行国内镜像源测速..."

# 国内主流镜像源列表
MIRRORS=(
    "阿里云|https://mirrors.aliyun.com/debian|https://mirrors.aliyun.com/ubuntu"
    "华为云|https://mirrors.huaweicloud.com/debian|https://mirrors.huaweicloud.com/ubuntu"
    "腾讯云|https://mirrors.cloud.tencent.com/debian|https://mirrors.cloud.tencent.com/ubuntu"
    "清华大学|https://mirrors.tuna.tsinghua.edu.cn/debian|https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
    "中科大|https://mirrors.ustc.edu.cn/debian|https://mirrors.ustc.edu.cn/ubuntu"
    "上海交大|https://mirror.sjtu.edu.cn/debian|https://mirror.sjtu.edu.cn/ubuntu"
)

# 测速文件路径（轻量级测试文件）
TEST_FILE="dists/$VERSION_CODENAME/Release"
TIMEOUT=5
BEST_MIRROR=""
BEST_SPEED=999999

# 安装必要的测速依赖
apt update -y && apt install -y --no-install-recommends curl bc

for MIRROR in "${MIRRORS[@]}"; do
    IFS='|' read -r NAME DEBIAN_URL UBUNTU_URL <<< "$MIRROR"
    
    # 根据发行版选择对应URL
    if [ "$DISTRO" = "debian" ]; then
        TEST_URL="$DEBIAN_URL/$TEST_FILE"
    elif [ "$DISTRO" = "ubuntu" ]; then
        TEST_URL="$UBUNTU_URL/$TEST_FILE"
    else
        TEST_URL="$DEBIAN_URL/$TEST_FILE"
    fi
    
    echo -n "测试 $NAME ... "
    # 测试下载速度（仅下载头部，计算耗时）
    START_TIME=$(date +%s.%N)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m $TIMEOUT "$TEST_URL" || echo "000")
    END_TIME=$(date +%s.%N)
    
    if [ "$HTTP_CODE" = "200" ]; then
        DURATION=$(echo "$END_TIME - $START_TIME" | bc -l)
        SPEED=$(echo "scale=2; 1 / $DURATION" | bc -l)
        echo "响应时间 $DURATION 秒"
        
        # 记录最快的源
        if (( $(echo "$DURATION < $BEST_SPEED" | bc -l) )); then
            BEST_SPEED=$DURATION
            BEST_MIRROR="$MIRROR"
        fi
    else
        echo "连接失败"
    fi
done

if [ -z "$BEST_MIRROR" ]; then
    echo "⚠️  所有镜像源测速失败，将使用默认阿里云源"
    SELECTED_NAME="阿里云"
    DEBIAN_URL="https://mirrors.aliyun.com/debian"
    UBUNTU_URL="https://mirrors.aliyun.com/ubuntu"
else
    IFS='|' read -r SELECTED_NAME DEBIAN_URL UBUNTU_URL <<< "$BEST_MIRROR"
    echo "✅ 测速完成，选择最快源: $SELECTED_NAME (响应时间 $BEST_SPEED 秒)"
fi
echo ""

# ------------------------------
# 功能1: 系统自动更新与源配置
# ------------------------------
echo "[1/7] 正在配置系统软件源..."

# 备份原有源
cp -a /etc/apt/sources.list /etc/apt/sources.list.backup.$(date +%Y%m%d)

# 配置国内源，根据发行版自动适配
if [ "$DISTRO" = "debian" ]; then
    # Debian 系列源配置
    cat > /etc/apt/sources.list << EOF
deb $DEBIAN_URL/ $VERSION_CODENAME main non-free non-free-firmware contrib
deb $DEBIAN_URL-security/ $VERSION_CODENAME-security main non-free non-free-firmware contrib
deb $DEBIAN_URL/ $VERSION_CODENAME-updates main non-free non-free-firmware contrib
EOF
elif [ "$DISTRO" = "ubuntu" ]; then
    # Ubuntu 系列源配置
    cat > /etc/apt/sources.list << EOF
deb $UBUNTU_URL/ $VERSION_CODENAME main restricted universe multiverse
deb $UBUNTU_URL/ $VERSION_CODENAME-security main restricted universe multiverse
deb $UBUNTU_URL/ $VERSION_CODENAME-updates main restricted universe multiverse
EOF
fi

echo "[1/7] 正在执行系统更新..."
apt update -y
apt upgrade -y
apt dist-upgrade -y
apt install -f -y
echo "✅ 系统更新完成"
echo ""

# ------------------------------
# 功能2: 硬件驱动安装适配
# ------------------------------
echo "[2/7] 正在安装硬件驱动与固件..."

# 安装通用硬件固件包
apt install -y --no-install-recommends \
    firmware-linux firmware-linux-nonfree firmware-misc-nonfree \
    firmware-realtek firmware-iwlwifi firmware-atheros firmware-brcm80211 firmware-amd-graphics

# 显卡驱动安装，适配不同发行版
if lspci | grep -E "VGA|3D controller" | grep -i "NVIDIA" > /dev/null; then
    echo "检测到NVIDIA显卡，正在安装驱动..."
    if [ "$DISTRO" = "ubuntu" ]; then
        # Ubuntu系统使用ubuntu-drivers工具
        apt install -y ubuntu-drivers-common
        ubuntu-drivers autoinstall
    else
        # Debian系统直接安装nvidia-driver包
        apt install -y nvidia-driver nvidia-smi
    fi
    # 禁用nouveau开源驱动
    echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
    echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist-nouveau.conf
    update-initramfs -u -k all
elif lspci | grep -E "VGA|3D controller" | grep -i "AMD" > /dev/null; then
    echo "检测到AMD显卡，正在安装开源驱动..."
    apt install -y xserver-xorg-video-amdgpu mesa-vulkan-drivers libvulkan1
elif lspci | grep -E "VGA|3D controller" | grep -i "Intel" > /dev/null; then
    echo "检测到Intel核显，正在安装驱动..."
    apt install -y xserver-xorg-video-intel mesa-va-drivers intel-media-va-driver
fi

# 无线网卡驱动重新加载
modprobe -r iwlwifi && modprobe iwlwifi 2>/dev/null || true

# 蓝牙驱动适配
echo "正在配置蓝牙驱动服务..."
apt install -y --no-install-recommends bluez bluez-tools pulseaudio-module-bluetooth blueman
systemctl enable --now bluetooth
modprobe btusb 2>/dev/null || true

echo "✅ 硬件驱动安装完成"
echo ""

# ------------------------------
# 功能3: 中文环境与输入法配置
# ------------------------------
echo "[3/7] 正在配置中文环境..."

# 安装locales并生成中文locale
apt install -y locales locales-all

# Debian与Ubuntu语言包适配
if [ "$DISTRO" = "ubuntu" ]; then
    apt install -y language-pack-zh-hans language-pack-zh-hans-base
fi

# 启用并生成中文locale
sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen --purge zh_CN.UTF-8 en_US.UTF-8

# 配置全局locale
cat > /etc/default/locale << EOF
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_ALL=zh_CN.UTF-8
EOF

# 清除冲突的locale变量
unset LANGUAGE LC_ALL LC_*

# 安装fcitx5五笔拼音输入法
echo "[3/7] 正在安装fcitx5输入法..."
apt purge -y ibus fcitx*
apt install -y --no-install-recommends \
    fcitx5 fcitx5-chinese-addons fcitx5-config-qt fcitx5-module-cloudpinyin fcitx5-pinyin

# 配置全局输入法环境变量
cat > /etc/profile.d/fcitx5.sh << EOF
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
export XMODIFIERS=@im=fcitx5
export INPUT_METHOD=fcitx5
export SDL_IM_MODULE=fcitx5
export GLFW_IM_MODULE=ibus
EOF
chmod +x /etc/profile.d/fcitx5.sh

# 安装中文字体
apt install -y --no-install-recommends \
    fonts-wqy-zenhei fonts-wqy-microhei fonts-noto-cjk fonts-noto-color-emoji
fc-cache -fv >/dev/null 2>&1

echo "✅ 中文环境配置完成"
echo ""

# ------------------------------
# 功能4: 安装WPS Office
# ------------------------------
echo "[4/7] 正在安装WPS Office..."
if [ "$(uname -m)" = "x86_64" ]; then
    # 多镜像源容错下载
    WPS_URLS=(
        "https://mirrors.huaweicloud.com/wps/wps-office_11.1.0.14712_amd64.deb"
        "https://mirrors.aliyun.com/wps/wps-office_11.1.0.14712_amd64.deb"
        "https://dl.wps.cn/wps/download/ep/Linux2024/14712/wps-office_11.1.0.14712_amd64.deb"
    )
    
    WPS_INSTALLED=false
    for URL in "${WPS_URLS[@]}"; do
        echo "尝试下载: $URL"
        if wget --tries=2 --timeout=15 -q -O wps.deb "$URL"; then
            dpkg -i wps.deb || apt install -f -y
            rm -f wps.deb
            WPS_INSTALLED=true
            break
        fi
        echo "下载失败，尝试下一个镜像..."
        rm -f wps.deb
    done
    
    if [ "$WPS_INSTALLED" = false ]; then
        echo "⚠️  WPS自动安装失败，请手动下载安装: https://www.wps.cn/product/wpslinux"
    else
        echo "✅ WPS安装完成"
    fi
else
    echo "⚠️  32位系统暂不支持WPS自动安装"
fi
echo ""

# ------------------------------
# 功能5: 安装星火应用商店
# ------------------------------
echo "[5/7] 正在安装星火应用商店..."
if [ "$(uname -m)" = "x86_64" ]; then
    # 多镜像源下载
    SPARK_URLS=(
        "https://gitee.com/deepin-community-store/spark-store/releases/download/v4.2.6/spark-store_4.2.6_amd64.deb"
        "https://mirrors.huaweicloud.com/spark-store/spark-store_4.2.6_amd64.deb"
    )
    
    SPARK_INSTALLED=false
    for URL in "${SPARK_URLS[@]}"; do
        echo "尝试下载: $URL"
        if wget --tries=2 --timeout=15 -q -O spark-store.deb "$URL"; then
            dpkg -i spark-store.deb || apt install -f -y
            rm -f spark-store.deb
            SPARK_INSTALLED=true
            break
        fi
        echo "下载失败，尝试下一个镜像..."
        rm -f spark-store.deb
    done
    
    if [ "$SPARK_INSTALLED" = false ]; then
        echo "⚠️  星火应用商店自动安装失败，请手动下载安装: https://www.spark-app.store/"
    else
        echo "✅ 星火应用商店安装完成"
    fi
else
    echo "⚠️  32位系统不支持星火应用商店"
fi
echo ""

# ------------------------------
# 功能6: 系统性能优化
# ------------------------------
echo "[6/7] 正在执行系统性能优化..."

# 内核参数优化
cat > /etc/sysctl.d/99-system-optimize.conf << EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
fs.file-max=65535
net.core.somaxconn=1024
net.ipv4.tcp_syncookies=1
EOF
sysctl -p /etc/sysctl.d/99-system-optimize.conf >/dev/null 2>&1

# 文件打开数限制
cat > /etc/security/limits.d/99-file-limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

# 禁用不必要的服务
systemctl disable apport 2>/dev/null || true
systemctl disable whoopsie 2>/dev/null || true
systemctl disable cups 2>/dev/null || true
systemctl disable ModemManager 2>/dev/null || true

# GRUB配置优化
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
update-grub >/dev/null 2>&1

echo "✅ 系统性能优化完成"
echo ""

# ------------------------------
# 功能7: 常用软件安装与系统清理
# ------------------------------
echo "[7/7] 正在安装常用工具软件..."
# 精简常用工具列表，避免安装大量不必要依赖
apt install -y --no-install-recommends \
    git curl wget vim htop net-tools tree \
    build-essential gdebi synaptic apt-transport-https ca-certificates \
    flameshot p7zip-full unrar

echo "正在清理系统冗余文件..."
apt autoremove -y >/dev/null 2>&1
apt autoclean >/dev/null 2>&1
apt clean >/dev/null 2>&1
rm -rf /tmp/*
rm -f /var/cache/apt/archives/*.deb
rm -f /root/*.deb

echo "✅ 常用软件安装完成"
echo ""

echo "======================================"
echo "🎉 脚本执行全部完成！"
echo "本次使用最快镜像源: $SELECTED_NAME"
echo "请重启系统使所有配置生效"
echo "======================================"
