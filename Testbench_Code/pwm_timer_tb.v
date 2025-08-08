module pwm_timer_tb;

    parameter base = 0; //? base address to start
    parameter clk_cycle = 10; // Clock cycle time
    // Control Register Bits
    localparam use_ext_clk      = 0;
    localparam pwm_mode         = 1;
    localparam counter_enable   = 2;
    localparam continuous_run   = 3;
    localparam pwm_output_en    = 4;
    localparam interrupt_flag   = 5;
    localparam use_input_dc     = 6;
    localparam reset_counter    = 7;

    localparam [15:0] CTRL_REG      = base + 16'b0;          // Control Register
    localparam [15:0] DIVISOR_REG   = base + 16'b10;         // Divisor Register
    localparam [15:0] PERIOD_REG0   = base + 16'b100;        // Period Register for Channel 0
    localparam [15:0] DC_REG0       = base + 16'b110;        // Duty Cycle Register for Channel 0
    localparam [15:0] PERIOD_REG1   = base + 16'b1000;       // Period Register for Channel 1
    localparam [15:0] DC_REG1       = base + 16'b1010;       // Duty Cycle Register for Channel 1
    localparam [15:0] PERIOD_REG2   = base + 16'b1100;       // Period Register for Channel 2
    localparam [15:0] DC_REG2       = base + 16'b1110;       // Duty Cycle Register for Channel 2
    localparam [15:0] PERIOD_REG3   = base + 16'b10000;      // Period Register for Channel 3
    localparam [15:0] DC_REG3       = base + 16'b10010;      // Duty Cycle Register for Channel 3
    localparam [15:0] COUNTERS_EN   = base + 16'b10100;      // Counters Enable Register
 
    //! wishbone interfacing compatible signals (B4)
    reg o_clk;                // Clock signal
    reg o_rst;                // Reset signal
    reg o_wb_cyc;             // Wishbone cycle indicator
    reg o_wb_stb;             // Wishbone strobe indicator
    reg o_wb_we;              // Wishbone write enable

    reg [15:0]o_wb_adr;       // Wishbone address bus
    reg [15:0]o_wb_data;      // Wishbone data bus (output)

    wire i_wb_ack;            // Wishbone acknowledge signal (input)
    wire [15:0]i_wb_data;     // Wishbone data bus (input)

    //! wishbone interfacing incompatible signals
    // External clock input for PWM/timer (used if use_ext_clk is set)
    reg o_extclk;

    // Input for external duty cycle value (used if use_input_dc is set)
    reg [15:0]o_DC;

    // Valid signal for external duty cycle input
    reg o_DC_valid;

    // PWM output signals for 4 channels
    wire [3:0]i_pwm;

    pwm_timer DUT(
        .i_clk      (o_clk),
        .i_rst      (o_rst),
        .i_extclk   (o_extclk),
        .i_DC       (o_DC),
        .i_DC_valid (o_DC_valid),
        .i_wb_cyc   (o_wb_cyc),
        .i_wb_stb   (o_wb_stb),
        .i_wb_we    (o_wb_we),
        .i_wb_adr   (o_wb_adr),
        .i_wb_data  (o_wb_data),
        .o_wb_data  (i_wb_data),
        .o_wb_ack   (i_wb_ack),
        .o_pwm      (i_pwm)
    );

    //! Internal signals for testing
    reg [15:0] outputs;
    reg [7:0] ctrls;

    //! Initialize signals
    initial 
    begin
        init();
    end

    //! Clock generation
    initial 
    begin
        forever begin
            #(clk_cycle/2) o_clk = (~o_clk);
        end
    end

    //! Testbench main execution
    initial 
    begin
        #100;
        //! test bench start here
        test_wishbone_operations();
        reset();
        test_pwm();
        reset();
        test_timer_interrupt();
        reset();
        test_test_down_clocking();
        reset();
        test_edge_cases();
        $stop;
    end

    task test_wishbone_operations(); //* wishbone operations test
        integer test_data;
        integer read_data;
        integer i;
        integer addr_list [0:10];
    begin 

        $display("Testing Wishbone Operations");
        // Test write/read for each register address

        //! Populate address list
        addr_list[0]  = CTRL_REG;      // 8 bits
        addr_list[1]  = DIVISOR_REG;   // 16 bits
        addr_list[2]  = PERIOD_REG0;   // 16 bits
        addr_list[3]  = DC_REG0;       // 16 bits
        addr_list[4]  = PERIOD_REG1;   // 16 bits
        addr_list[5]  = DC_REG1;       // 16 bits
        addr_list[6]  = PERIOD_REG2;   // 16 bits
        addr_list[7]  = DC_REG2;       // 16 bits
        addr_list[8]  = PERIOD_REG3;   // 16 bits
        addr_list[9]  = DC_REG3;       // 16 bits
        addr_list[10] = COUNTERS_EN;   // 4 bits

        //! CTRL_REG (8 bits)
        ctrls = $random;
        set_ctrls(counter_enable, 1'b0);
        set_ctrls(interrupt_flag, 1'b0);
        test_data = {8'b0, ctrls};
        #5;
        wb_write(addr_list[0], test_data[7:0]);
        wb_read(addr_list[0], read_data);
        if (read_data[7:0] !== test_data[7:0])
            $error("? Addr %h write/read failed! Expected: %h, Got: %h", addr_list[0], test_data[7:0], read_data[7:0]);
        else
            $display("? Addr %h write/read successful! %h", addr_list[0], read_data[7:0]);



        //! Other registers (16 bits)
        for (i = 1; i <= 9; i = i + 1) begin
            test_data = $random;
            wb_write(addr_list[i], test_data[15:0]);
            wb_read(addr_list[i], read_data[15:0]);
            if (read_data[15:0] !== test_data[15:0])
                $error("? Addr %h write/read failed! Expected: %h, Got: %h", addr_list[i], test_data[15:0], read_data[15:0]);
            else
                $display("? Addr %h write/read successful! %h", addr_list[i], read_data[15:0]);
        end

        //! RCOUNTERS_EN (4 bits)
        test_data = $random;
        wb_write(addr_list[10], test_data[3:0]);
        wb_read(addr_list[10], read_data);
        if (read_data[3:0] !== test_data[3:0])
            $error("? Addr %h write/read failed! Expected: %h, Got: %h", addr_list[10], test_data[3:0], read_data[3:0]);
        else
            $display("? Addr %h write/read successful! %h", addr_list[10], read_data[3:0]);
        $display("Wishbone Operations Test Complete");
        #20;
    end 
    endtask
        
    task test_pwm(); //* PWM generation test
        reg [15:0] period, duty_cycle;
    begin

        $display("Testing PWM Generation");

        //! Test 50% Duty Cycle
        $display("Testing PWM 50%% Duty Cycle");
        period = 100;

        duty_cycle = period / 2;                  // Duty cycle = 50% of period
        wb_write(PERIOD_REG0, period);            // Write period value to PERIOD_REG0
        wb_write(DC_REG0, duty_cycle);            // Write duty cycle value to DC_REG0
        wb_write(COUNTERS_EN, {12'b0, 4'b1});     // Enable PWM channel 0
        wb_write(DIVISOR_REG, 16'd1);             // Set clock divisor to 1 (no division)
        clr_ctrls();                              // Clear control register bits
        set_ctrls(pwm_mode, 1'b1);                // Set PWM mode
        set_ctrls(counter_enable, 1'b1);          // Enable counter
        set_ctrls(pwm_output_en, 1'b1);           // Enable PWM output
        wb_write(CTRL_REG, {8'b0, ctrls});        // Write control register
        #(period * 5 * clk_cycle);                // Wait for 5 periods
        $display("PWM 50%% Test Complete");

        //! Test 25% Duty Cycle
        $display("Testing PWM 25%% Duty Cycle");
        duty_cycle = period / 4;                  // 25% duty cycle
        wb_write(DC_REG0, duty_cycle);            // DC = 50 (50%)
        #(period * 5 * clk_cycle);                // Wait for 5 periods
        $display("PWM 25%% Test Complete");

        //! Test random Duty Cycle/ Period
        $display("Testing random Duty Cycle/ Period");
        repeat (5) begin
            period = $urandom_range(50, 250); // Random period between 50 and 250
            duty_cycle = $urandom_range(0, period - 1); // Random DC less than period
            $display("Random Period: %d, Duty Cycle: %d", period, duty_cycle);
            wb_write(PERIOD_REG0, period);  // Set random period
            wb_write(DC_REG0, duty_cycle); // set random duty cycle
            #(period * 5 * clk_cycle); // Wait for 5 periods
        end
        $display("PWM Tests Complete");
    end
    endtask 

    task test_timer_interrupt(); //* Timer Interrupt Test
        reg [15:0] period;
    begin
        // Test Timer Interrupt
        $display("Testing Timer Interrupt / Clear Interrupt Flag");

        //! Oneshot Timer Interrupt
        $display("Testing oneshot Timer Interrupt");
        repeat (10) begin
            period = $urandom_range(50, 250); // Random period between 50 and 250
            wb_write(PERIOD_REG0, period);  // Set random period
            wb_write(DIVISOR_REG, 16'd1);   // No division
            clr_ctrls();
            set_ctrls(pwm_mode, 1'b0);       // Timer mode
            set_ctrls(counter_enable, 1'b1); // Enable counter
            wb_write(CTRL_REG, {8'b0, ctrls});
            wb_write(COUNTERS_EN, {12'b0, 4'b1}); // Enable channel 0
            #((period + 10) * clk_cycle); // Wait for one period + some extra time        
            
            //? Check interrupt flag
            if(i_pwm[0]) 
            begin
                $display("? INTERRUPT GENERATED! Period: %d", period);
                set_ctrls(interrupt_flag, 1'b0); // Clear interrupt flag
                wb_write(CTRL_REG, {8'b0, ctrls});
                if(i_pwm[0])
                    $display("ERROR: Interrupt flag not cleared");
                else
                    $display("? INTERRUPT CLEARED!   Period: %d", period);
            end
            else 
                $display("? INTERRUPT NOT GENERATED! Period: %d", period);
        end

        //! Continuous Timer Interrupt
        $display("Testing continuous Timer Interrupt");
        repeat (10) begin
            wb_write(COUNTERS_EN, {12'b0, 4'b1}); // Enable channel 0
            period = $urandom_range(50, 250); // Random period between 50 and 250
            wb_write(PERIOD_REG0, period);  // Set random period
            wb_write(DIVISOR_REG, 16'd1);   // No division
            clr_ctrls();
            set_ctrls(continuous_run, 1'b1); // Continuous run
            set_ctrls(pwm_mode, 1'b0);       // Timer mode
            set_ctrls(counter_enable, 1'b1); // Enable counter
            wb_write(CTRL_REG, {8'b0, ctrls});
            #((period + 10) * clk_cycle); // Wait for one period + some extra time        
            
            //? Check interrupt flag
            if(i_pwm[0]) 
            begin
                $display("? INTERRUPT GENERATED! Period: %d", period);
                set_ctrls(interrupt_flag, 1'b0); // Clear interrupt flag
                wb_write(CTRL_REG, {8'b0, ctrls});
                if(i_pwm[0])
                    $display("ERROR: Interrupt flag not cleared");
                else
                    $display("? INTERRUPT CLEARED!   Period: %d", period);
            end
            else 
                $display("? INTERRUPT NOT GENERATED! Period: %d", period);
        end
        $display("Timer Interrupt Tests Complete");
    end
    endtask

    task test_test_down_clocking(); //* Down Clocking Test
        reg [15:0] period , divisor;
    begin
        $display("Testing Down Clocking");

        //! Down Clocking with Divisor = 2
        $display("Testing Down Clocking with Divisor = 2 , timer mode");
        period = 20; // Set period to 20
        divisor = 2; // Set divisor to 2
        wb_write(DIVISOR_REG, divisor);   // Divisor = 2
        wb_write(PERIOD_REG0, period);   // Period = 20
        clr_ctrls();
        set_ctrls(pwm_mode, 1'b0);       // Timer mode
        set_ctrls(counter_enable, 1'b1); // Enable counter
        wb_write(CTRL_REG, {8'b0, ctrls});
        wb_write(COUNTERS_EN, {12'b0, 4'b1}); // Enable channel 0
        #((period + 10) * clk_cycle * divisor ); // Wait for one period + some extra time
        
        //? Check interrupt flag
        if(i_pwm[0])
            $display("? INTERRUPT GENERATED! Period: %d , divisor: %d", period , divisor);
        else
            $display("? INTERRUPT NOT GENERATED! Period: %d , divisor: %d", period , divisor);
        set_ctrls(interrupt_flag, 1'b0); // Clear interrupt flag

        //! Down Clocking with Divisor = 10
        $display("Testing Down Clocking with Divisor = 10 , timer mode");
        period = 20; // Set period to 20
        divisor = 10; // Set divisor to 10
        wb_write(DIVISOR_REG, divisor);   // Divisor = 10
        wb_write(PERIOD_REG0, period);   // Period = 20
        clr_ctrls();
        set_ctrls(pwm_mode, 1'b0);       // Timer mode
        set_ctrls(counter_enable, 1'b1); // Enable counter
        wb_write(CTRL_REG, {8'b0, ctrls});
        wb_write(COUNTERS_EN, {12'b0, 4'b1}); // Enable channel 0
        #((period + 10) * clk_cycle * divisor ); // Wait for one period + some extra time
        
        //? Check interrupt flag
        if(i_pwm[0])
            $display("? INTERRUPT GENERATED! Period: %d , divisor: %d", period , divisor);
        else
            $display("? INTERRUPT NOT GENERATED! Period: %d , divisor: %d", period , divisor);
        set_ctrls(interrupt_flag, 1'b0); // Clear interrupt flag

        //! Down Clocking with PWM mode and random divisors
        $display("Testing Down Clocking with PWM mode and random divisors");
        repeat (5) begin
            reset();
            period = $urandom_range(20, 100);
            divisor = $urandom_range(1, 20);
            wb_write(DIVISOR_REG, divisor);
            wb_write(PERIOD_REG0, period);
            wb_write(DC_REG0, period / 2); // 50% duty cycle
            clr_ctrls();
            set_ctrls(pwm_mode, 1'b1);       // PWM mode
            set_ctrls(counter_enable, 1'b1); // Enable counter
            set_ctrls(pwm_output_en, 1'b1);  // Enable PWM output
            wb_write(CTRL_REG, {8'b0, ctrls});
            wb_write(COUNTERS_EN, {12'b0, 4'b1}); // Enable channel 0
            $display("PWM mode: Period=%d, Divisor=%d, Duty=%d", period, divisor, period/2);
            #(period * 5 * clk_cycle * divisor); // Wait for 5 periods
        end
        $display("PWM mode with random divisors test complete");
        $display("Down Clocking Tests Complete");

    end
    endtask


    task test_edge_cases(); //* Edge Cases Test
        reg [15:0] period, duty_cycle , divisor;
    begin
        $display("Testing Edge Cases");

        //! Edge Case: Duty Cycle > Period
        $display("Sub-test: Duty Cycle > Period");
        // Reset divisor to 1 for normal operation
        period = 50; // Set period to 50
        divisor = 1; // Set divisor to 1
        duty_cycle = 80; // Set duty cycle to 80 (greater than period)
        wb_write(DIVISOR_REG, divisor);
        wb_write(PERIOD_REG0, period);   // Period = 50
        wb_write(DC_REG0, duty_cycle);       // DC = 80 (> Period)
        clr_ctrls();
        set_ctrls(pwm_mode, 1'b1);
        set_ctrls(counter_enable, 1'b1);
        set_ctrls(pwm_output_en, 1'b1);
        wb_write(CTRL_REG, {8'b0, ctrls});
        wb_write(COUNTERS_EN, {12'b0, 4'b1}); // Enable channel 0
        $display("Expected: PWM should be always HIGH");
        #((period) * clk_cycle * divisor * 5); // Wait for 5 periods
        $display("Sub-test: Duty Cycle > Period complete");
        
        //! Edge Case: Duty Cycle = 0
        $display("Sub-test: Divisor = 0");
        divisor = 0; // Set divisor to 0
        period = 30; // Set period to 30
        duty_cycle = 15; // Set duty cycle to 15 (normal)
        wb_write(DIVISOR_REG, divisor);    // Divisor = 0
        wb_write(PERIOD_REG0, period);   // Period = 30
        wb_write(DC_REG0, duty_cycle);       // DC = 15 (normal)
        $display("Expected: Should work as Divisor = 1");
        #((period) * clk_cycle * 5); // Wait for 5 periods
        $display("Sub-test: Divisor = 0 complete");

        //! Edge Case: Manual Counter Reset
        $display("Sub-test: Manual Counter Reset");
        clr_ctrls();
        set_ctrls(pwm_mode, 1'b1);
        set_ctrls(counter_enable, 1'b1);
        set_ctrls(pwm_output_en, 1'b1);
        set_ctrls(reset_counter, 1'b1);  // Manual reset
        wb_write(CTRL_REG, {8'b0, ctrls});
        #(period * clk_cycle); // Wait for half period

        // Release manual reset
        clr_ctrls();
        set_ctrls(pwm_mode, 1'b1);
        set_ctrls(counter_enable, 1'b1);
        set_ctrls(pwm_output_en, 1'b1);
        wb_write(CTRL_REG, {8'b0, ctrls});
        $display("Counter manually reset and restarted");
        #((period) * clk_cycle * 5); // Wait for 5 periods
        $display("Sub-test: Manual Counter Reset complete");

        //! Multi PWM Channel Edge with different period and different DC
        $display("Testing Multi PWM Channel Edge with different period and different DC");
        reset();
        period = 200; // Set period to 100
        wb_write(PERIOD_REG0, period);  // Period = 200
        wb_write(DC_REG0, period/2);        // DC = 100
        wb_write(PERIOD_REG1, period);  // Period = 200
        wb_write(DC_REG1, period/4);        // DC = 50
        wb_write(PERIOD_REG2, period/2);  // Period = 200
        wb_write(DC_REG2, period/8);        // DC = 25
        wb_write(PERIOD_REG3, period/4);  // Period = 200
        wb_write(DC_REG3, period/10);       // DC = 20
        clr_ctrls();
        set_ctrls(pwm_mode, 1'b1);       // PWM mode
        set_ctrls(counter_enable, 1'b1); // Enable counter
        set_ctrls(pwm_output_en, 1'b1);  // Enable PWM output
        wb_write(CTRL_REG, {8'b0, ctrls});
        wb_write(COUNTERS_EN, {12'b0, 4'b1111}); // Enable all channels
        $display("Expected: All channels should output PWM with different duty cycles");
        #((period) * clk_cycle * 5); // Wait for 5 periods
        $display("Multi PWM Channel Edge Test Complete");

        //! External Duty Cycle Source
        $display("Sub-test: External Duty Cycle Source for PWM Channel 0");
        reset();
        period = 100;
        wb_write(PERIOD_REG0, period);  // Set period
        wb_write(DIVISOR_REG, 16'd1);    // No division
        clr_ctrls();
        set_ctrls(pwm_mode, 1'b1);       // PWM mode
        set_ctrls(counter_enable, 1'b1); // Enable counter
        set_ctrls(pwm_output_en, 1'b1);  // Enable PWM output
        set_ctrls(use_input_dc, 1'b1);   // Use external DC
        wb_write(CTRL_REG, {8'b0, ctrls});
        wb_write(COUNTERS_EN, {12'b0, 4'b1}); // Enable channel 0

        // Provide external duty cycle values
        $display("External DC: 25");
        set_extDC(25);
        #(period * clk_cycle * 2);
        $display("External DC: 75");
        set_extDC(75);
        #(period * clk_cycle * 2);
        $display("External DC: 50");
        set_extDC(50);
        #(period * clk_cycle * 2);
        o_DC_valid = 1'b0; // Deassert valid after last update
        $display("External Duty Cycle Source Test Complete");

        $display("Edge Cases Tests Complete");

    end
    endtask  

    //!helper tasks

    //? Initialize signals
    task init();
    begin
        o_rst = 1'b1;
        o_wb_cyc = 1'b0;
        o_wb_stb = 1'b0;
        o_wb_we = 1'b0;
        o_wb_adr = 16'b0;
        o_wb_data = 16'b0;
        o_DC = 16'b0;
        o_DC_valid = 1'b0;
        o_extclk = 1'b0;
        o_clk = 1'b0;
        #10;
        o_rst = 1'b0;
    end
    endtask

    //? Reset task
    task reset();
    begin
        o_rst = 1'b1;
        #10;
        o_rst = 1'b0;
    end
    endtask

    //? Wishbone write task
    task wb_write(input [15:0]adr, input [15:0]data);
    begin
        @ (posedge o_clk);
        o_wb_cyc = 1'b1;
        o_wb_stb = 1'b1;
        o_wb_we  = 1'b1;
        o_wb_adr = adr;
        o_wb_data = data;
        wait(i_wb_ack);
        @ (posedge o_clk);
        o_wb_stb = 1'b0;
        o_wb_cyc = 1'b0;
        @ (negedge i_wb_ack);
    end
    endtask

    //? Set external clock half period task
    task set_extclk_half_period(input [15:0] half_period, input [15:0] duration_cycles);
        integer i;
    begin
        for (i = 0; i < duration_cycles; i = i + 1) begin
            o_extclk = 1'b1;
            #(half_period);
            o_extclk = 1'b0;
            #(half_period);
        end
    end
    endtask

    //? Set external duty cycle task
    task set_extDC(input [15:0] DC);
    begin
        @ (posedge o_clk);
        o_DC = DC;
        o_DC_valid = 1'b1;
    end
    endtask

    //? Wishbone read task
    task wb_read(input [15:0]adr, output [15:0]data);
    begin
        @ (posedge o_clk);
        o_wb_cyc = 1'b1;
        o_wb_stb = 1'b1;
        o_wb_adr = adr;
        o_wb_we  = 1'b0;
        wait(i_wb_ack);
        @ (posedge o_clk);
        data = i_wb_data;
        o_wb_stb = 1'b0;
        o_wb_cyc = 1'b0;
        @ (negedge i_wb_ack);
    end
    endtask

    //? Clear control signals task
    task clr_ctrls();
    begin
        ctrls = 8'b0;
    end
    endtask

    //? Set control signals task
    task set_ctrls(input integer bit, input value);
    begin
        ctrls[bit] = value;
    end
    endtask


endmodule
