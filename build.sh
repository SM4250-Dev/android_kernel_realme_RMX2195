#!/bin/bash
set -e

# Core Config
KERNELNAME="StrombreakerX"
VARIANT="Stable"
DEVICE="RMX2195"
DEFCONFIG="RMX2195_defconfig"
FILES="Image.gz"

# Telegram 
CHATID="$TG_CHAT_ID"
BOT_MSG="https://api.telegram.org/bot$TG_TOKEN/sendMessage"
BOT_DOC="https://api.telegram.org/bot$TG_TOKEN/sendDocument"

# Functions
msg() { echo -e "[*] $1" }
status() { echo -e "[⏳] $1" }
tg() { curl -s -X POST "$BOT_MSG" -d chat_id="$CHATID" -d parse_mode=html -d text="$1" >/dev/null}
tg_file() { curl -s -F document=@"$1" "$BOT_DOC" -F chat_id="$CHATID" -F caption="$2" >/dev/null }

clone() {
    status "Cloning Clang..."
    git clone --depth=1 https://github.com/techyminati/android_prebuilts_clang_host_linux-x86_clang-6443078 clang
    export PATH="$PWD/clang/bin:$PATH"
}

setup() {
    export KBUILD_BUILD_USER="mnrdnn"
    PROCS=$(nproc)
    KERVER=$(make kernelversion 2>/dev/null || echo "unknown")
    COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commit")
    
    MAKE_CMD="ARCH=arm64 \
              CC=clang \
              LD=ld.lld \
              AR=llvm-ar \
              NM=llvm-nm \
              STRIP=llvm-strip \
              OBJCOPY=llvm-objcopy \
              CLANG_TRIPLE=aarch64-linux-gnu- \
              CROSS_COMPILE=aarch64-linux-gnu- \
              CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
}

build() {
    [ $INCREMENTAL = 0 ] && { make mrproper 2>/dev/null \
    rm -rf out}
    
    status "Configuring..."
    make O=out $DEFCONFIG >/dev/null 2>&1
    
    tg "🔨 <b>Building $KERNELNAME $VARIANT</b>%0A📱 $DEVICE%0A🔧 $(clang --version | head -n1 | cut -d'(' -f1)%0A📦 $KERVER"
    
    START=$(date +%s)
    status "Compiling..."
    make -j$(nproc) O=out $MAKE_CMD Image.gz
    END=$(date +%s)
    DIFF=$((END-START))
    
    if [ -f out/arch/arm64/boot/$FILES ]; then
        SIZE=$(du -h out/arch/arm64/boot/$FILES | cut -f1)
        msg "Success! $((DIFF/60))m $((DIFF%60))s | $SIZE"
        tg "✅ <b>Build Success</b>%0A⏱️ $((DIFF/60))m $((DIFF%60))s%0A📦 $SIZE"
        upload
    else
        msg "Build failed!"
        tg "❌ <b>Build Failed</b>%0A⏱️ $((DIFF/60))m $((DIFF%60))s"
        exit 1
    fi
}

upload() {
    ZIP="$KERNELNAME-$VARIANT-$(date +%Y%m%d-%H%M).zip"
    AK=https://github.com/UdyneO2/Anykernel
    AK_B=RMX2195
    AKN=RMX2195-AnyKernel
    git clone --depth=1 $AK -b $AK_B $AKN && rm -rf $AKN/.git $AKN/.github
      if [[ -f out/arch/arm64/boot/Image.gz ]]; then
        cp out/arch/arm64/boot/Image.gz $AKN/Image.gz
        echo -e "Image.gz found"
      else
        echo -e "Image.gz not found"
      fi
    cd $AKN
    zip -r9 "/tmp/$ZIP" * 2>/dev/null
    tg_file "/tmp/$ZIP" "✅ <b>$KERNELNAME $VARIANT</b>%0A📱 $DEVICE%0A⏱️ $((DIFF/60))m $((DIFF%60))s"
    msg "Done!"
    cd ..
}

# Run
clone
setup
build
