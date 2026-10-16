#!/bin/zsh
set -eu
phone_source="${0:A:h}"
phone_destination="${1:?Pass the destination app bundle}"
mkdir -p "$phone_destination/Contents/Resources/PhoneControl"
cp "$phone_source/../LICENSE" "$phone_destination/Contents/Resources/PhoneControl/LICENSE.txt"
cp "$phone_source/../../../Windows/PhoneTrackpad-QRCoder-LICENSE.txt" "$phone_destination/Contents/Resources/PhoneControl/QRCoder-LICENSE.txt"
for phone_arch in arm64 x64; do
  dotnet publish "$phone_source/ThreeE.PhoneHost.csproj" -c Release -r "osx-$phone_arch" --self-contained true \
    -p:UseAppHost=true -p:DebugType=None -o "$phone_destination/Contents/Resources/PhoneControl/$phone_arch"
  chmod +x "$phone_destination/Contents/Resources/PhoneControl/$phone_arch/ThreeE.PhoneHost"
  phone_native_arch="$phone_arch"
  if [[ "$phone_arch" == x64 ]]; then phone_native_arch=x86_64; fi
  xcrun clang -arch "$phone_native_arch" -dynamiclib -Wall -Wextra -mmacosx-version-min=14.0 \
    -framework CoreGraphics -framework CoreFoundation "$phone_source/PhoneNative.c" \
    -o "$phone_destination/Contents/Resources/PhoneControl/$phone_arch/libThreeEPhoneNative.dylib"
  # Sign every native image before signing its containing app.
  while IFS= read -r -d '' phone_binary; do
    codesign --force --sign - "$phone_binary"
  done < <(find "$phone_destination/Contents/Resources/PhoneControl/$phone_arch" -type f \( -name '*.dylib' -o -name 'ThreeE.PhoneHost' -o -name 'createdump' \) -print0)
done
