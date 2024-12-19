echo "Compilation starts"
# define   -I for include path  -y for library path  -o for output file
# $1 is the first argument passed to the script
iverilog -I ../core -y ../core -o sim.out $1
echo "Generate waveforms"
vvp -n sim.out
echo "View waveforms"
gtkwave sim_out.vcd
