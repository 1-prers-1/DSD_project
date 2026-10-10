#!/usr/bin/env bash
# Regression runner. Run from the repo root: ./scripts/run_sim.sh
set -e
cd "$(dirname "$0")/.."

mkdir -p sim_out

echo "=== Compiling RTL + testbench (iverilog) ==="
iverilog -g2012 -o sim_out/sim.out \
    rtl/line_buffer.sv \
    rtl/frame_controller.sv \
    rtl/mac_pipeline.sv \
    rtl/accelerator_top.sv \
    tb/stream_source.sv \
    tb/stream_sink.sv \
    tb/tb_top.sv

run_case () {
    local name=$1; local input=$2; local expected=$3; local size=$4; local extra_args=$5
    echo ""
    echo "=== Test: $name ==="
    vvp sim_out/sim.out +INPUT="$input" +OUTPUT="sim_out/${name}_rtl_output.hex" +SIZE=$size $extra_args
    python3 golden_model/compare.py --expected "$expected" --actual "sim_out/${name}_rtl_output.hex" --size $size
}

# Regenerate golden vectors (safe to rerun; deterministic with fixed seeds)
python3 golden_model/gen_test_image.py --size 8 --pattern random      --seed 1 --name t0
python3 golden_model/gen_test_image.py --size 8 --pattern constant    --seed 0 --name t1
python3 golden_model/gen_test_image.py --size 8 --pattern impulse     --seed 0 --name t2
python3 golden_model/gen_test_image.py --size 8 --pattern checkerboard --seed 0 --name t3
python3 golden_model/gen_test_image.py --size 8 --pattern all_zero    --seed 0 --name t4
python3 golden_model/gen_test_image.py --size 8 --pattern all_max     --seed 0 --name t5
python3 golden_model/gen_test_image.py --size 8 --pattern random      --seed 42 --name t6
python3 golden_model/gen_test_image.py --size 8 --pattern random      --seed 99 --name t7

PASS=0
FAIL=0

run_one () {
    if run_case "$1" "$2" "$3" "$4" "$5"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        echo "!!! $1 FAILED !!!"
    fi
}

run_one "t0_clean"        golden_model/vectors/t0_input.hex golden_model/vectors/t0_expected.hex 8 ""
run_one "t0_gaps_stalls"  golden_model/vectors/t0_input.hex golden_model/vectors/t0_expected.hex 8 "+GAPS=1 +STALLS=1 +SEED=7"
run_one "t1_constant"     golden_model/vectors/t1_input.hex golden_model/vectors/t1_expected.hex 8 ""
run_one "t2_impulse"      golden_model/vectors/t2_input.hex golden_model/vectors/t2_expected.hex 8 ""
run_one "t3_checkerboard" golden_model/vectors/t3_input.hex golden_model/vectors/t3_expected.hex 8 "+GAPS=1 +SEED=3"
run_one "t4_all_zero"     golden_model/vectors/t4_input.hex golden_model/vectors/t4_expected.hex 8 ""
run_one "t5_all_max"      golden_model/vectors/t5_input.hex golden_model/vectors/t5_expected.hex 8 "+STALLS=1 +SEED=5"
run_one "t6_rand_gaps"    golden_model/vectors/t6_input.hex golden_model/vectors/t6_expected.hex 8 "+GAPS=1 +SEED=11"
run_one "t7_rand_both"    golden_model/vectors/t7_input.hex golden_model/vectors/t7_expected.hex 8 "+GAPS=1 +STALLS=1 +SEED=13"

echo ""
echo "=== SUMMARY: $PASS passed, $FAIL failed ==="
if [ $FAIL -ne 0 ]; then exit 1; fi
