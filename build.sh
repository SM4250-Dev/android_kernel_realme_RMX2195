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

# Default values
INCREMENTAL=0  # Add this variable - it was missing
DIFF=0  # Initialize for safety

# Functions
msg() { echo -e "[*] $1"; }
status() { echo -e "[⏳] $1"; }
tg() { curl -s -X POST "$BOT_MSG" -d chat_id="$CHATID" -d parse_mode=html -d text="$1" >/dev/null 2>&1; }
tg_file() { curl -s -F document=@"$1" "$BOT_DOC" -F chat_id="$CHATID" -F caption="$2" >/dev/null 2>&1; }

clone() {
    status "Cloning Clang..."
    git clone --depth=1 https://github.com/techyminati/android_prebuilts_clang_host_linux-x86_clang-6443078 clang || { msg "Failed to clone Clang"; exit 1; }
    export PATH="$PWD/clang/bin:$PATH"
    
    # Verify clang is available
    if ! command -v clang &> /dev/null; then
        msg "Clang not found in PATH"
        exit 1
    fi
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
    if [ "$INCREMENTAL" = "0" ]; then 
        make mrproper 2>/dev/null || true
        rm -rf out 2>/dev/null || true
    fi
    
    # Create out directory if it doesn't exist
    mkdir -p out
    
    status "Configuring..."
    if ! make O=out $DEFCONFIG >/dev/null 2>&1; then
        msg "Failed to configure kernel"
        exit 1
    fi
    
    # Get clang version safely
    CLANG_VER=$(clang --version 2>/dev/null | head -n1 | cut -d'(' -f1 || echo "clang")
    
    tg "🔨 <b>Building $KERNELNAME $VARIANT</b>%0A📱 $DEVICE%0A🔧 $CLANG_VER%0A📦 $KERVER"
    
    START=$(date +%s)
    status "Compiling..."
    
    # Build with error checking
    if ! make -j$(nproc) O=out $MAKE_CMD $FILES; then
        END=$(date +%s)
        DIFF=$((END-START))
        msg "Build failed!"
        tg "❌ <b>Build Failed</b>%0A⏱️ $((DIFF/60))m $((DIFF%60))s"
        exit 1
    fi
    
    END=$(date +%s)
    DIFF=$((END-START))
    
    if [ -f "out/arch/arm64/boot/$FILES" ]; then
        SIZE=$(du -h "out/arch/arm64/boot/$FILES" | cut -f1)
        msg "Success! $((DIFF/60))m $((DIFF%60))s | $SIZE"
        tg "✅ <b>Build Success</b>%0A⏱️ $((DIFF/60))m $((DIFF%60))s%0A📦 $SIZE"
        upload
    else
        msg "Build failed - output file not found!"
        tg "❌ <b>Build Failed</b>%0A⏱️ $((DIFF/60))m $((DIFF%60))s%0A❌ Output file missing"
        exit 1
    fi
}

upload() {
    ZIP="$KERNELNAME-$VARIANT-$(date +%Y%m%d-%H%M).zip"
    AK="https://github.com/UdyneO2/Anykernel"
    AK_B="RMX2195"
    AKN="RMX2195-AnyKernel"
    
    # Clone AnyKernel with error checking
    if ! git clone --depth=1 "$AK" -b "$AK_B" "$AKN"; then
        msg "Failed to clone AnyKernel"
        exit 1
    fi
    
    # Remove unnecessary files
    rm -rf "$AKN/.git" "$AKN/.github" 2>/dev/null || true
    
    if [[ -f "out/arch/arm64/boot/Image.gz" ]]; then
        cp "out/arch/arm64/boot/Image.gz" "$AKN/Image.gz"
        echo -e "Image.gz found and copied"
    else
        echo -e "Image.gz not found"
        exit 1
    fi
    
    cd "$AKN" || exit 1
    
    # Create zip
    if ! zip -r9 "/tmp/$ZIP" * 2>/dev/null; then
        msg "Failed to create zip"
        exit 1
    fi
    
    # Upload with caption
    tg_file "/tmp/$ZIP" "✅ <b>$KERNELNAME $VARIANT</b>%0A📱 $DEVICE%0A⏱️ $((DIFF/60))m $((DIFF%60))s"
    
    msg "Done!"
    cd ..
    
    # Cleanup
    rm -f "/tmp/$ZIP" 2>/dev/null || true
    rm -rf "$AKN" 2>/dev/null || true
}

# Main execution
main() {
    # Check required environment variables
    if [ -z "$TG_CHAT_ID" ] || [ -z "$TG_TOKEN" ]; then
        msg "Warning: TG_CHAT_ID or TG_TOKEN not set. Telegram notifications disabled."
    fi
    
    clone
    setup
    build
}

# Run main function
main
