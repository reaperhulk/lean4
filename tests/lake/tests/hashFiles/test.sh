#!/usr/bin/env bash
source ../common.sh

./clean.sh

# Keep the Lake cache local to the test
export LAKE_CACHE_DIR=
unset LAKE_WRITE_HASH_FILES

#-------------------------------------------------------------------------------
# This test covers the `.hash` files Lake writes next to module build outputs
# and the `writeHashFiles` / `LAKE_WRITE_HASH_FILES` setting that disables them.
#-------------------------------------------------------------------------------

LIB=.lake/build/lib/lean
IR=.lake/build/ir
NO_BUILD_CODE=3

hash_files() {
  find .lake/build -name '*.hash' | sort
}

test_no_hash_files() {
  test_cmd_eq "" hash_files
}

echo 'def bar := 1' > Bar.lean

echo "# TEST: default writes hash files"
# External tools rely on these (e.g., Mathlib's `lake exe cache` requires
# `.olean.hash`, `.ilean.hash`, and `.c.hash` before it packs a module).
test_run build
for f in $LIB/Bar.olean $LIB/Bar.ilean $IR/Bar.c \
  $LIB/Mod.olean $LIB/Mod.olean.server $LIB/Mod.olean.private \
  $LIB/Mod.ilean $LIB/Mod.ir $LIB/Mod.ir.sig $IR/Mod.c
do
  test_exp -f "$f.hash"
done

echo "# TEST: disabled hash files are not written on a fresh build"
./clean.sh
echo 'def bar := 1' > Bar.lean
test_run -f noHashFiles.toml build
test_exp -f $LIB/Bar.olean
test_exp -f $LIB/Mod.olean.private
test_no_hash_files

echo "# TEST: disabled hash files are not created by an up-to-date build"
test_run -f noHashFiles.toml build --no-build
test_not_out "Built" -f noHashFiles.toml build
test_no_hash_files

echo "# TEST: disabled hash files are not written on a rebuild"
echo 'def bar := 2' > Bar.lean
test_out "Built Foo" -f noHashFiles.toml build
test_no_hash_files

echo "# TEST: up-to-date output hashes come from the trace"
# Tamper with an up-to-date output. Lake trusts the hash recorded in the trace
# (as it would a `.hash` file), so dependents stay up-to-date ...
echo "tampered" >> $LIB/Bar.olean
test_run -f noHashFiles.toml build --no-build
test_no_hash_files
# ... whereas `--rehash` recomputes the hash and detects the change,
# still without writing a `.hash` file.
test_status $NO_BUILD_CODE -f noHashFiles.toml build --no-build --rehash
test_no_hash_files
test_cmd rm $LIB/Bar.olean
test_out "Built Bar" -f noHashFiles.toml build
test_no_hash_files

echo "# TEST: traces without outputs fall back to hashing the files"
if command -v jq > /dev/null; then # skip if no jq found
  jq '.outputs = null' $LIB/Bar.trace > Bar.trace.tmp
  mv Bar.trace.tmp $LIB/Bar.trace
  test_run -f noHashFiles.toml build --no-build
  test_no_hash_files
fi

echo "# TEST: disabled hash files with an archive round trip"
test_out "Built Bar:ltar" -f noHashFiles.toml build +Bar:ltar
test_exp -f $IR/Bar.ltar
test_cmd rm $LIB/Bar.olean
test_out "leantar" -f noHashFiles.toml build Bar --no-build -v
test_exp -f $LIB/Bar.olean
test_run -f noHashFiles.toml build --no-build
test_no_hash_files

echo "# TEST: disabled hash files with the artifact cache"
LAKE_ARTIFACT_CACHE=true test_run -f noHashFiles.toml build
LAKE_ARTIFACT_CACHE=true test_run -f noHashFiles.toml build --no-build
test_no_hash_files
rm -rf .lake/build
LAKE_ARTIFACT_CACHE=true LAKE_RESTORE_ARTIFACTS=true \
  test_run -f noHashFiles.toml build --no-build
test_exp -f $LIB/Foo.olean
test_no_hash_files
rm -rf .lake/cache

echo "# TEST: the environment variable disables hash files"
./clean.sh
echo 'def bar := 1' > Bar.lean
LAKE_WRITE_HASH_FILES=false test_run build
LAKE_WRITE_HASH_FILES=false test_run build --no-build
test_no_hash_files

echo "# TEST: switching an existing build directory to disabled hash files"
./clean.sh
echo 'def bar := 1' > Bar.lean
test_run build
test_exp -f $LIB/Bar.olean.hash
test_run -f noHashFiles.toml build --no-build
# Rebuilding a module removes its now unused `.hash` files
echo 'def bar := 3' > Bar.lean
test_out "Built Bar" -f noHashFiles.toml build
test_exp ! -f $LIB/Bar.olean.hash
test_exp ! -f $LIB/Bar.ilean.hash
test_exp ! -f $IR/Bar.c.hash
# ... and re-enabling them works as before
echo 'def bar := 4' > Bar.lean
test_out "Built Bar" build
test_exp -f $LIB/Bar.olean.hash

# Cleanup
./clean.sh
