#!/usr/bin/env bash
# check_config.sh — assert mandatory config gates; sourced or executed with .config arg
CFG="${1:?usage: check_config.sh <path/to/.config>}"

get() {
  awk -v k="$1" '$0 ~ "^"k"=" {sub("^"k"=", ""); print; found=1; exit}
       $0 == "# "k" is not set" {print "n"; found=1; exit}' "$CFG"
}

fail=0
need_y=(
  CONFIG_ARCH_PINEAPPLE
  CONFIG_KSU
  CONFIG_KSU_SUSFS
  CONFIG_MODULES
  CONFIG_MODVERSIONS
  CONFIG_MODULE_SIG
  CONFIG_MODULE_SIG_PROTECT
  CONFIG_CFI_CLANG
  CONFIG_KPROBES
)
for k in "${need_y[@]}"; do
  [ "$(get "$k")" = "y" ] || { echo "FAIL: $k must be y"; fail=1; }
done

need_n=(
  CONFIG_KSU_SUSFS_SUS_SU
)
for k in "${need_n[@]}"; do
  [ "$(get "$k")" = "n" ] || { echo "FAIL: $k must be n (SUS_SU bootloops non-GKI)"; fail=1; }
done

# LTO must be none (CFI with LTO clang LTO changes type hashes vs stock)
if [ "$(get CONFIG_LTO)" = "y" ] && [ -z "$(get CONFIG_LTO_NONE)" ]; then
  echo "FAIL: LTO must be CONFIG_LTO_NONE=y"; fail=1
fi
[ "$(get CONFIG_LTO_NONE)" = "y" ] || { echo "FAIL: CONFIG_LTO_NONE must be y"; fail=1; }

exit $fail
