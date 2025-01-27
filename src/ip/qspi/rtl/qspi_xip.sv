`timescale 1ns/1ps
module qspi_xip (

  input logic clk_i,
  input logic rst_ni,
    
  input logic [23:0]  addr_i,
  input logic         req_i,
  output logic [31:0] rdata_o,
  output logic        rvalid_o,
    
  input logic [3:0]  qspi_i,
  output logic [3:0] qspi_o,
  output logic [3:0] qspi_oe,
  output logic       qspi_csb,
  output logic       qspi_clk

);

  typedef enum logic [1:0] {IDLE, TRANSMIT,RECEIVER} xip_state_t;
    
  logic count_enb;
  logic count_clear;
  logic chip_sel;
  logic t_load;
  logic t_enb;
  logic [31:0] t_data;
  logic [3:0] q_oeb;
  logic r_enb;
  logic d_valid;
  logic clken_d, clken_q;
  logic [5:0] max_count;
  logic [5:0] clk_count;
  logic temp_enb;
  logic reg0;
  logic reg1;
  logic [4:0] reg_mcount8;
  logic [4:0] reg_mcount9;
  logic [4:0] reg_mcount10;
  logic [4:0] reg_mcount6;
  logic [4:0] reg_mcount2;
  logic [4:0] reg_mcount0;
  logic [31:0] reg_data0;
  logic [3:0] reg_oeb0;
  logic [3:0] reg_oeb15;
    
  xip_state_t   x_cstate, x_nstate;
    
  // xip next state logic 
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      x_nstate <= IDLE;
      qspi_csb <= 1'b1;
      clken_q  <= 1'b0;
      rvalid_o <= '0;
    end else begin
      x_nstate <= x_cstate;
      qspi_csb <= chip_sel;
      clken_q  <= clken_d;
      rvalid_o <= (d_valid && (rdata_o != '0));
    end
  end
    
  always_comb begin
    if(clken_q) begin
      qspi_clk = clk_i;
    end else begin
      qspi_clk = '1;
    end
  end
    
  always_ff @(negedge qspi_clk or negedge rst_ni) begin
    if(!rst_ni) begin
      qspi_oe  <= 4'b1111;
    end else begin
      qspi_oe  <= q_oeb;
    end  
  end

  always_comb begin
    x_cstate = x_nstate;
    unique case(x_nstate)
      IDLE: begin        
              if(req_i) begin
                x_cstate = TRANSMIT;
                clken_d  = 1'b1;
                count_enb   = 1'b0;
                count_clear = 1'b1;
                max_count   = 6'd17;
                chip_sel    = 1'b0;
                t_load      = 1'b0;
                t_enb       = 1'b0;
                t_data      = {addr_i, 8'h0};
                q_oeb       = 4'b1111;
                r_enb       = 1'b0;
                d_valid     = 1'b0;
                temp_enb    = 1'b0;
              end else begin
                x_cstate = IDLE;
                clken_d  = 1'b0;
                count_enb   = 1'b0;
                count_clear = 1'b1;
                max_count   = '0;
                chip_sel    = 1'b1;
                t_load      = 1'b0;
                t_enb       = 1'b0;
                t_data      = '0;
                q_oeb       = '0;
                r_enb       = 1'b0;
                d_valid     = 1'b0;
                temp_enb    = 1'b0;
              end
            end
      TRANSMIT: begin    
                  if(clk_count != 16) begin
                    x_cstate = TRANSMIT;
                    clken_d  = 1'b1;
                    count_enb   = 1'b1;
                    count_clear = 1'b0;
                    chip_sel    = 1'b0;
                    max_count   = 6'd17;
                    r_enb       = 1'b0;
                    
                    if(clk_count > 0) begin
                      t_load      = 1'b0;
                    end else begin
                      t_load      = 1'b1;
                    end
                    q_oeb       = 4'b1111;
                    t_enb       = 1'b1;
                    t_data      = {addr_i, 8'h0};
                    d_valid     = 1'b0;
                  end else begin
                    x_cstate = RECEIVER;
                    clken_d  = 1'b1;
                    chip_sel    = 1'b0;
                    count_enb   = 1'b0;
                    count_clear = 1'b1;
                    max_count   = 5'd9;
                    t_load      = 1'b0;
                    t_enb       = 1'b1;
                    t_data      = '0;
                    q_oeb       = 4'b0;
                    r_enb       = 1'b1;
                    d_valid     = 1'b0;
                    temp_enb    = 1'b0;
                  end
                end
      RECEIVER: begin     
                  if(clk_count != 7) begin
                    x_cstate = RECEIVER;
                    clken_d  = 1'b1;
                    max_count   = 5'd9;
                    if(clk_count > 5) begin
                      chip_sel    = 1'b1;
                      q_oeb       = 4'b1111;
                    end else begin
                      chip_sel    = 1'b0;
                      q_oeb       = 4'b0;
                    end
                    
                    count_enb   = 1'b1;
                    count_clear = 1'b0;
                    chip_sel    = 1'b0;
                    t_load      = 1'b0;
                    t_enb       = 1'b0;
                    t_data      = '0;
                    q_oeb       = '0;
                    r_enb       = 1'b1;
                    d_valid     = 1'b0;
                    temp_enb    = 1'b0;
                  end else begin
                    x_cstate = IDLE;
                    clken_d  = 1'b0;
                    chip_sel    = 1'b1;
                    count_enb   = 1'b0;
                    count_clear = 1'b1;
                    max_count   = '0;
                    t_load      = 1'b0;
                    t_enb       = 1'b0;
                    t_data      = '0;
                    q_oeb       = '0;
                    r_enb       = 1'b1;
                    d_valid     = 1'b1;
                    temp_enb    = 1'b0;
                  end
                end
      default: begin        
                  clken_d  = clken_q;
                  count_enb   = 1'b0;
                  count_clear = 1'b1;
                  max_count   = 6'd17;
                  chip_sel    = 1'b1;
                  t_load      = 1'b0;
                  t_enb       = 1'b0;
                  t_data      = '0;
                  q_oeb       = '0;
                  r_enb       = 1'b0;
                  d_valid     = 1'b0;
                  temp_enb    = 1'b0;
                end
    endcase
  end


  clk_counter u_clk_counter(
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .enable_i   (count_enb),
    .clear_i    (count_clear),
    .max_count_i(max_count),
    .clk_count_o(clk_count)
  );


  qspi_transmitter u_transmitter(

    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .p_data_i   (t_data),
    .t_enb_i    (t_enb),
    .t_load_i   (t_load),
    .s_out_o    (qspi_o)
  );

  qspi_receiver u_receiver(
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .s_in_i ((|qspi_oe) ? 4'b0 : qspi_i),
    .enb_i  (r_enb),
    .p_out_o(rdata_o)
  );

endmodule
