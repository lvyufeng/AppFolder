#!/bin/bash
#
# Builds a WidgetKit module that adds the one declaration the OS exports but the
# SDK does not publish: `WidgetConfiguration.preferredBackgroundStyle(_:)`.
#
# Why this exists. iOS ships the symbol — it is in the SDK's WidgetKit.tbd, and
# it is what makes a widget take the system's Liquid Glass plate. But no
# swiftinterface in the SDK declares it, so a plain `import WidgetKit` cannot
# see it and the call will not compile. This script copies the SDK's own textual
# interface, appends the missing declarations, and compiles the result into a
# module. `-I "$TARGET_TEMP_DIR"` on the widget target puts that module ahead of
# the SDK's, so the source can write the call directly.
#
# Why not pure Swift. The alternative is extending WidgetConfiguration with a
# member of the same name. That compiles — and then the linker resolves the call
# to the SDK's real generic, opaque-return symbol with the wrong ABI, and the
# extension dies at launch. The shape has to come from a module built against
# the interface, which is what this does.
#
# The declarations added below are shape only. Both symbols remain undefined
# externals that load from the system's WidgetKit at runtime, which is the point:
# nothing is reimplemented here.

set -euo pipefail

: "${SDKROOT:?overlay: SDKROOT is unset}"
: "${ARCHS:?overlay: ARCHS is unset}"
: "${TARGET_TEMP_DIR:?overlay: TARGET_TEMP_DIR is unset}"
: "${PLATFORM_NAME:?overlay: PLATFORM_NAME is unset}"
: "${IPHONEOS_DEPLOYMENT_TARGET:?overlay: IPHONEOS_DEPLOYMENT_TARGET is unset}"

# The module is emitted as a *directory* holding one entry per arch, not as a
# single `WidgetKit.swiftmodule` file. A bare file records the one triple it was
# built for and is refused by every other: built at the widget's 18.0 it fails
# the slices that compile at 27.0 with "created for incompatible target
# arm64-apple-ios27.0-simulator", and building it at 27.0 only moves the refusal
# to the slices that compile at 18.0.
#
# Two things make the directory work, and both were measured:
#   * An entry is looked up as `<arch>-apple-<platform>.swiftmodule` — no
#     deployment version in the name. Naming the entry after the triple it was
#     built for (`arm64-apple-ios18.0-simulator.swiftmodule`) finds nothing, and
#     the client falls back to the SDK's module with no error to say so: the
#     failure reads "has no member 'preferredBackgroundStyle'".
#   * That lookup ignores the deployment version, so one 18.0 entry serves a
#     client compiling at 27.0. The compile below therefore keeps the real
#     `-target`; only the file name is stripped.
#
# Rewriting the interface's own `-target` is not a way out. Built without a
# version the clang importer loses the SDK's version defaulting and the system
# interface stops typechecking ("'EnvironmentValues' is only available in
# iOS 13.0 or newer"). The flags stay as Apple shipped them.
interface_dir="$SDKROOT/System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule"

# The device SDK ships no `arm64-apple-ios.swiftinterface` — one arm64e
# interface serves both — so each arch falls back to the arm64 interface.
fallback_interface="arm64-apple-ios-simulator"
[ "$PLATFORM_NAME" = "iphonesimulator" ] || fallback_interface="arm64e-apple-ios"

module_dir="$TARGET_TEMP_DIR/WidgetKit.swiftmodule"
# TARGET_TEMP_DIR survives between builds, and an earlier run of this script
# left a *file* here. A file and a directory cannot share the name.
if [ -e "$module_dir" ] && [ ! -d "$module_dir" ]; then rm -f "$module_dir"; fi
mkdir -p "$module_dir"

built=0
for arch in $ARCHS; do
  if [ "$PLATFORM_NAME" = "iphonesimulator" ]; then
    source_interface="$interface_dir/$arch-apple-ios-simulator.swiftinterface"
    target="$arch-apple-ios$IPHONEOS_DEPLOYMENT_TARGET-simulator"
    entry="$arch-apple-ios-simulator"
  else
    source_interface="$interface_dir/$arch-apple-ios.swiftinterface"
    target="$arch-apple-ios$IPHONEOS_DEPLOYMENT_TARGET"
    entry="$arch-apple-ios"
  fi
  [ -f "$source_interface" ] || source_interface="$interface_dir/$fallback_interface.swiftinterface"
  if [ ! -f "$source_interface" ]; then
    echo "overlay: no WidgetKit swiftinterface for arch '$arch' under $interface_dir" >&2
    exit 1
  fi

  cat "$source_interface" > "$TARGET_TEMP_DIR/WidgetKit-$arch.swiftinterface"
  cat >> "$TARGET_TEMP_DIR/WidgetKit-$arch.swiftinterface" <<'INTERFACE'

// ---------------------------------------------------------------------------
// Appended by Scripts/widgetkit-overlay.sh. Shape only — see that script.
public enum WidgetBackgroundStyle : Swift::Int, Swift::RawRepresentable {
  case opaque
  case transparent
  case blur
  public init?(rawValue: Swift::Int)
  public typealias RawValue = Swift::Int
  public var rawValue: Swift::Int { get }
}
extension SwiftUI::WidgetConfiguration {
  public func preferredBackgroundStyle(_ style: WidgetKit::WidgetBackgroundStyle) -> some SwiftUI::WidgetConfiguration
}
INTERFACE

xcrun swift-frontend -compile-module-from-interface "$TARGET_TEMP_DIR/WidgetKit-$arch.swiftinterface" \
    -o "$module_dir/$entry.swiftmodule" \
    -module-name WidgetKit \
    -sdk "$SDKROOT" \
    -target "$target" \
    -module-cache-path "$TARGET_TEMP_DIR/module-cache"

  echo "overlay: WidgetKit.swiftmodule/$entry.swiftmodule (built for $target)"
  built=$((built + 1))
done

[ "$built" -gt 0 ] || { echo "overlay: ARCHS is empty" >&2; exit 1; }