// ============================================================
// run.f  -  VCS filelist for tb_axi_interconnect_wrap_1x8
//
// Run from the  run/  directory:
//   cd /home/student/Documents/316/soc_project_packet_buffering/run
//   vcs -full64 -sverilog -f run.f -o simv -l compile.log
//   ./simv -l sim.log
// ============================================================

// ---- Language / debug flags ---------------------------------
-sverilog
-debug_access+all
-kdb
-timescale=1ns/1ps

// ---- FSDB PLI (Verdi U-2023.03-SP1, absolute path) ----------
+define+DUMP_FSDB
-P /home/student/snps_tools_target/verdi/U-2023.03-SP1/share/PLI/VCS/LINUX64/novas.tab
/home/student/snps_tools_target/verdi/U-2023.03-SP1/share/PLI/VCS/LINUX64/pli.a

// ---- RTL source files  (relative to run/) -------------------
../rtl/priority_encoder.v
../rtl/arbiter.v
../rtl/axi_interconnect.v
../rtl/axi_interconnect_wrap_1x8.v

// ---- Testbench ----------------------------------------------
../tb/tb_axi_interconnect_wrap_1x8.v
