module pwm_timer (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_extclk,
    input  wire [15:0] i_DC,
    input  wire        i_DC_valid,
    input  wire        i_wb_cyc,
    input  wire        i_wb_stb,
    input  wire        i_wb_we,
    input  wire [15:0] i_wb_adr,
    input  wire [15:0] i_wb_data,
    output reg  [15:0] o_wb_data,
    output reg         o_wb_ack,
    output reg  [3:0]  o_pwm        // 4 PWM outputs
);

    // Control Register Bit Indices
    localparam use_ext_clk      = 0;
    localparam pwm_mode         = 1;
    localparam counter_enable   = 2;
    localparam continuous_run   = 3;
    localparam pwm_output_en    = 4;
    localparam interrupt_flag   = 5;
    localparam use_input_dc     = 6;
    localparam reset_counter    = 7;

    reg [7:0]   Ctrl;
    reg [15:0]  Divisor;
    reg [15:0]  Period [3:0];
    reg [15:0]  DC [3:0];
    reg [15:0]  clk_div_cnt;
    reg [15:0]  main_counter [3:0];
    reg [15:0]  actual_DC [3:0];
    reg [15:0]  safe_DC [3:0];
    reg [3:0]   counters_enable;

    wire selected_clk = Ctrl[use_ext_clk] ? i_extclk : i_clk;
    wire count_tick = (Divisor <= 1) || (clk_div_cnt == Divisor - 1);
    wire Invalid_divisor_flag = (Divisor <= 1 || Divisor > 65535);

    // Clock divider logic
    always @(posedge selected_clk or posedge i_rst)
    begin
        if (i_rst || Ctrl[reset_counter])
            clk_div_cnt <= 0;
        else if (Ctrl[counter_enable] && !Invalid_divisor_flag)
            clk_div_cnt <= count_tick ? 0 : clk_div_cnt + 1;
    end

    // PWM/timer logic for 4 channels
    genvar ch;
    generate
        for (ch = 0; ch < 4; ch = ch + 1)
        begin: pwm_loop

            reg [15:0] next_counter;

            // Select between external or internal DC
            always @(*) begin
                actual_DC[ch] = (Ctrl[use_input_dc] && i_DC_valid) ? i_DC : DC[ch];
                safe_DC[ch]   = (actual_DC[ch] > Period[ch]) ? Period[ch] : actual_DC[ch];
            end

            // Main counter and PWM/timer behavior
            always @(posedge selected_clk or posedge i_rst)
            begin
                if (i_rst || Ctrl[reset_counter]) begin
                    main_counter[ch] <= 0;
                    o_pwm[ch] <= 0;
                    if (ch == 0) Ctrl[interrupt_flag] <= 0; // only once
                end 
                else if (count_tick && Ctrl[counter_enable] && counters_enable[ch]) begin
                    if (Ctrl[pwm_mode]) begin
                        next_counter = (main_counter[ch] >= (Period[ch]==0?Period[ch]:Period[ch] -1)) ? 0 : main_counter[ch] + 1;
                        main_counter[ch] <= next_counter;

                        if (Ctrl[pwm_output_en])
                        begin
                            o_pwm[ch] <= (next_counter < safe_DC[ch]);
                        end
                        else
                        begin
                            o_pwm[ch] <= 0;
                        end
                    end else begin
                        if (main_counter[ch] >= Period[ch]) begin
                            Ctrl[interrupt_flag] <= 1;
                            main_counter[ch] <= 0;
                            o_pwm[ch] <= 1;
                            if (!Ctrl[continuous_run])
                                counters_enable[ch] <= 0;
                        end else begin
                            main_counter[ch] <= main_counter[ch] + 1;
                            // o_pwm[ch] <= 0;
                        end
                    end
                end
            end
        end
    endgenerate

    // Wishbone read/write interface
    integer i;
    always @(posedge i_clk or posedge i_rst)
    begin
        if (i_rst) begin
            Ctrl <= 0;
            Divisor <= 16'd1;
            o_pwm <= 4'b0000;
            for (i = 0; i < 4; i = i + 1) begin
                Period[i] <= 0;
                DC[i] <= 0;
            end
            counters_enable <= 0;
            o_wb_data <= 0;
            o_wb_ack <= 0;
        end 
        else begin
            o_wb_ack <= (i_wb_cyc && i_wb_stb && !o_wb_ack);

            if (i_wb_cyc && i_wb_stb) begin
                if (i_wb_we) begin
                    case (i_wb_adr)
                        0: begin
                            Ctrl[7:6] <= i_wb_data[7:6];

                            // Clear interrupt flag and all channels
                            if (i_wb_data[5] == 1'b0) begin
                                Ctrl[interrupt_flag] <= 0;
                                o_pwm <= 0;
                            end

                            Ctrl[4:0] <= i_wb_data[4:0];
                        end
                        2: Divisor <= i_wb_data;
                        4,8,12,16: Period[(i_wb_adr - 4)>>2] <= i_wb_data;
                        6,10,14,18: DC[(i_wb_adr - 6)>>2] <= i_wb_data;
                        20: counters_enable <= i_wb_data[3:0]; // write interrupt enables
                        default: ;
                    endcase
                end else begin
                    case (i_wb_adr)
                        0: o_wb_data <= {8'd0, Ctrl};
                        2: o_wb_data <= Divisor;
                        4,8,12,16: o_wb_data <= Period[(i_wb_adr - 4)>>2];
                        6,10,14,18: o_wb_data <= DC[(i_wb_adr - 6)>>2];
                        20: o_wb_data <= {12'd0, counters_enable}; // read interrupt enables 
                        default: o_wb_data <= 0;
                    endcase
                end
            end
        end
    end

endmodule
