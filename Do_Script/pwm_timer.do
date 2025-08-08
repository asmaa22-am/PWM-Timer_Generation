vlib work
vlog pwm_timer.v pwm_timer_tb.v
vsim -voptargs=+acc work.pwm_timer_tb
add wave * DUT.main_counter DUT.Ctrl
run -all
#quit -sim