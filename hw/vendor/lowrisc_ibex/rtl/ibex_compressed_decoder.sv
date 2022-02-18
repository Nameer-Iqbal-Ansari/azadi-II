// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Compressed instruction decoder
 *
 * Decodes RISC-V compressed instructions into their RV32 equivalent.
 * This module is fully combinatorial, clock and reset are used for
 * assertions only.
 */

`include "prim_assert.sv"

module ibex_compressed_decoder (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    input  logic [31:0] instr_i,
    output logic [31:0] instr_o,
    output logic        is_compressed_o,
    output logic        illegal_instr_o
);
  import ibex_pkg::*;

  // valid_i indicates if instr_i is valid and is used for assertions only.
  // The following signal is used to avoid possible lint errors.
  logic unused_valid;
  assign unused_valid = valid_i;

  ////////////////////////
  // Compressed decoder //
  ////////////////////////

  always_comb begin
    // By default, forward incoming instruction, mark it as legal.
    instr_o         = instr_i;
    illegal_instr_o = 1'b0;

    // Check if incoming instruction is compressed.
    unique case (instr_i[1:0])
      // C0
      2'b00: begin
        unique case (instr_i[15:13])
          3'b000: begin
            // c.addi4spn -> addi rd', x2, imm
            instr_o = {2'b0, instr_i[10:7], instr_i[12:11], instr_i[5],
                       instr_i[6], 2'b00, 5'h02, 3'b000, 2'b01, instr_i[4:2], {OPCODE_OP_IMM}};
            if (instr_i[12:5] == 8'b0)  illegal_instr_o = 1'b1;
          end

          3'b010: begin
            // c.lw -> lw rd', imm(rs1')
            instr_o = {5'b0, instr_i[5], instr_i[12:10], instr_i[6],
                       2'b00, 2'b01, instr_i[9:7], 3'b010, 2'b01, instr_i[4:2], {OPCODE_LOAD}};
          end

          3'b011: begin
            // c.flw -> flw frd`, imm(rs1)
            instr_o = {5'b0, instr_i[5], instr_i[12:10], instr_i[6],
                       2'b00, 2'b01, instr_i[9:7], 3'b010, 2'b01, instr_i[4:2], {OPCODE_LOAD_FP}};
          end

          3'b110: begin
            // c.sw -> sw rs2', imm(rs1')
            instr_o = {5'b0, instr_i[5], instr_i[12], 2'b01, instr_i[4:2],
                       2'b01, instr_i[9:7], 3'b010, instr_i[11:10], instr_i[6],
                       2'b00, {OPCODE_STORE}};
          end

          3'b111: begin
            // c.fsw -> fsw frs2`, imm(rs1`)
            instr_o = {5'b0, instr_i[5], instr_i[12], 2'b01, instr_i[4:2],
                       2'b01, instr_i[9:7], 3'b010, instr_i[11:10], instr_i[6],
                       2'b00, {OPCODE_STORE_FP}};
          end

          3'b001,
          3'b100,
          3'b101: begin
            illegal_instr_o = 1'b1;
          end

          default: begin
            illegal_instr_o = 1'b1;
          end
        endcase
      end

      // C1
      //
      // Register address checks for RV32E are performed in the regular instruction decoder.
      // If this check fails, an illegal instruction exception is triggered and the controller
      // writes the actual faulting instruction to mtval.
      2'b01: begin
        unique case (instr_i[15:13])
          3'b000: begin
            // c.addi -> addi rd, rd, nzimm
            // c.nop
            instr_o = {{6 {instr_i[12]}}, instr_i[12], instr_i[6:2],
                       instr_i[11:7], 3'b0, instr_i[11:7], {OPCODE_OP_IMM}};
          end

          3'b001, 3'b101: begin
            // 001: c.jal -> jal x1, imm
            // 101: c.j   -> jal x0, imm
            instr_o = {instr_i[12], instr_i[8], instr_i[10:9], instr_i[6],
                       instr_i[7], instr_i[2], instr_i[11], instr_i[5:3],
                       {9 {instr_i[12]}}, 4'b0, ~instr_i[15], {OPCODE_JAL}};
          end

          3'b010: begin
            // c.li -> addi rd, x0, nzimm
            // (c.li hints are translated into an addi hint)
            instr_o = {{6 {instr_i[12]}}, instr_i[12], instr_i[6:2], 5'b0,
                       3'b0, instr_i[11:7], {OPCODE_OP_IMM}};
          end

          3'b011: begin
            // c.lui -> lui rd, imm
            // (c.lui hints are translated into a lui hint)
            instr_o = {{15 {instr_i[12]}}, instr_i[6:2], instr_i[11:7], {OPCODE_LUI}};

            if (instr_i[11:7] == 5'h02) begin
              // c.addi16sp -> addi x2, x2, nzimm
              instr_o = {{3 {instr_i[12]}}, instr_i[4:3], instr_i[5], instr_i[2],
                         instr_i[6], 4'b0, 5'h02, 3'b000, 5'h02, {OPCODE_OP_IMM}};
            end

            if ({instr_i[12], instr_i[6:2]} == 6'b0) illegal_instr_o = 1'b1;
          end

          3'b100: begin
            unique case (instr_i[11:10])
              2'b00,
              2'b01: begin
                // 00: c.srli -> srli rd, rd, shamt
                // 01: c.srai -> srai rd, rd, shamt
                // (c.srli/c.srai hints are translated into a srli/srai hint)
                instr_o = {1'b0, instr_i[10], 5'b0, instr_i[6:2], 2'b01, instr_i[9:7],
                           3'b101, 2'b01, instr_i[9:7], {OPCODE_OP_IMM}};
                if (instr_i[12] == 1'b1)  illegal_instr_o = 1'b1;
              end

              2'b10: begin
                // c.andi -> andi rd, rd, imm
                instr_o = {{6 {instr_i[12]}}, instr_i[12], instr_i[6:2], 2'b01, instr_i[9:7],
                           3'b111, 2'b01, instr_i[9:7], {OPCODE_OP_IMM}};
              end

              2'b11: begin
                unique case ({instr_i[12], instr_i[6:5]})
                  3'b000: begin
                    // c.sub -> sub rd', rd', rs2'
                    instr_o = {2'b01, 5'b0, 2'b01, instr_i[4:2], 2'b01, instr_i[9:7],
                               3'b000, 2'b01, instr_i[9:7], {OPCODE_OP}};
                  end

                  3'b001: begin
                    // c.xor -> xor rd', rd', rs2'
                    instr_o = {7'b0, 2'b01, instr_i[4:2], 2'b01, instr_i[9:7], 3'b100,
                               2'b01, instr_i[9:7], {OPCODE_OP}};
                  end

                  3'b010: begin
                    // c.or  -> or  rd', rd', rs2'
                    instr_o = {7'b0, 2'b01, instr_i[4:2], 2'b01, instr_i[9:7], 3'b110,
                               2'b01, instr_i[9:7], {OPCODE_OP}};
                  end

                  3'b011: begin
                    // c.and -> and rd', rd', rs2'
                    instr_o = {7'b0, 2'b01, instr_i[4:2], 2'b01, instr_i[9:7], 3'b111,
                               2'b01, instr_i[9:7], {OPCODE_OP}};
                  end

                  3'b100,
                  3'b101,
                  3'b110,
                  3'b111: begin
                    // 100: c.subw
                    // 101: c.addw
                    illegal_instr_o = 1'b1;
                  end

                  default: begin
                    illegal_instr_o = 1'b1;
                  end
                endcase
              end

              default: begin
                illegal_instr_o = 1'b1;
              end
            endcase
          end

          3'b110, 3'b111: begin
            // 0: c.beqz -> beq rs1', x0, imm
            // 1: c.bnez -> bne rs1', x0, imm
            instr_o = {{4 {instr_i[12]}}, instr_i[6:5], instr_i[2], 5'b0, 2'b01,
                       instr_i[9:7], 2'b00, instr_i[13], instr_i[11:10], instr_i[4:3],
                       instr_i[12], {OPCODE_BRANCH}};
          end

          default: begin
            illegal_instr_o = 1'b1;
          end
        endcase
      end

      // C2
      //
      // Register address checks for RV32E are performed in the regular instruction decoder.
      // If this check fails, an illegal instruction exception is triggered and the controller
      // writes the actual faulting instruction to mtval.
      2'b10: begin
        unique case (instr_i[15:13])
          3'b000: begin
            // c.slli -> slli rd, rd, shamt
            // (c.ssli hints are translated into a slli hint)
            instr_o = {7'b0, instr_i[6:2], instr_i[11:7], 3'b001, instr_i[11:7], {OPCODE_OP_IMM}};
            if (instr_i[12] == 1'b1)  illegal_instr_o = 1'b1; // reserved for custom extensions
          end

          3'b010: begin
            // c.lwsp -> lw rd, imm(x2)
            instr_o = {4'b0, instr_i[3:2], instr_i[12], instr_i[6:4], 2'b00, 5'h02,
                       3'b010, instr_i[11:7], OPCODE_LOAD};
            if (instr_i[11:7] == 5'b0)  illegal_instr_o = 1'b1;
          end

          3'b011: begin
            // c.flwsp -> flw frd, imm(x2)
            instr_o = {4'b0, instr_i[3:2], instr_i[12], instr_i[6:4], 2'b00, 5'h02,
                       3'b010, instr_i[11:7], OPCODE_LOAD_FP};
          end

          3'b100: begin
            if (instr_i[12] == 1'b0) begin
              if (instr_i[6:2] != 5'b0) begin
                // c.mv -> add rd/rs1, x0, rs2
                // (c.mv hints are translated into an add hint)
                instr_o = {7'b0, instr_i[6:2], 5'b0, 3'b0, instr_i[11:7], {OPCODE_OP}};
              end else begin
                // c.jr -> jalr x0, rd/rs1, 0
                instr_o = {12'b0, instr_i[11:7], 3'b0, 5'b0, {OPCODE_JALR}};
                if (instr_i[11:7] == 5'b0)  illegal_instr_o = 1'b1;
              end
            end else begin
              if (instr_i[6:2] != 5'b0) begin
                // c.add -> add rd, rd, rs2
                // (c.add hints are translated into an add hint)
                instr_o = {7'b0, instr_i[6:2], instr_i[11:7], 3'b0, instr_i[11:7], {OPCODE_OP}};
              end else begin
                if (instr_i[11:7] == 5'b0) begin
                  // c.ebreak -> ebreak
                  instr_o = {32'h00_10_00_73};
                end else begin
                  // c.jalr -> jalr x1, rs1, 0
                  instr_o = {12'b0, instr_i[11:7], 3'b000, 5'b00001, {OPCODE_JALR}};
                end
              end
            end
          end

          3'b110: begin
            // c.swsp -> sw rs2, imm(x2)
            instr_o = {4'b0, instr_i[8:7], instr_i[12], instr_i[6:2], 5'h02, 3'b010,
                       instr_i[11:9], 2'b00, {OPCODE_STORE}};
          end

          3'b111: begin
            // c.fswsp -> fsw frs2, imm(x2)
            instr_o = {4'b0, instr_i[8:7], instr_i[12], instr_i[6:2], 5'h02, 3'b010,
                       instr_i[11:9], 2'b00, {OPCODE_STORE_FP}};
          end

          3'b001,
          3'b101: begin
            illegal_instr_o = 1'b1;
          end

          default: begin
            illegal_instr_o = 1'b1;
          end
        endcase
      end

      // Incoming instruction is not compressed.
      2'b11:;

      default: begin
        illegal_instr_o = 1'b1;
      end
    endcase
  end

  assign is_compressed_o = (instr_i[1:0] != 2'b11);

  ////////////////
  // Assertions //
  ////////////////

  // Selectors must be known/valid.
  `ASSERT(IbexInstrLSBsKnown, valid_i |->
      !$isunknown(instr_i[1:0]))
  `ASSERT(IbexC0Known1, (valid_i && (instr_i[1:0] == 2'b00)) |->
      !$isunknown(instr_i[15:13]))
  `ASSERT(IbexC1Known1, (valid_i && (instr_i[1:0] == 2'b01)) |->
      !$isunknown(instr_i[15:13]))
  `ASSERT(IbexC1Known2, (valid_i && (instr_i[1:0] == 2'b01) && (instr_i[15:13] == 3'b100)) |->
      !$isunknown(instr_i[11:10]))
  `ASSERT(IbexC1Known3, (valid_i &&
      (instr_i[1:0] == 2'b01) && (instr_i[15:13] == 3'b100) && (instr_i[11:10] == 2'b11)) |->
      !$isunknown({instr_i[12], instr_i[6:5]}))
  `ASSERT(IbexC2Known1, (valid_i && (instr_i[1:0] == 2'b10)) |->
      !$isunknown(instr_i[15:13]))

    ////////////////////////////
  //  Functional coverages  //
  ////////////////////////////
  
  `ifdef AZADI_FC

  ////////////////////////////////////////////
  // Covergroup for compressed instructions //
  ////////////////////////////////////////////
  covergroup compressed_instruction_cg ()@((instr_i[15:13]) || instr_i[1:0]) ;
    // Functional coverage for Register-Based Loads and Stores and Integer Register-Immediate Operation
    C0_ADDI :  coverpoint ((instr_i[15:13] == 3'b000) && 
                          (!(instr_i[12:5] == 8'b0))) iff  (instr_i[1:0] == 2'b00);
    C0_LW   :  coverpoint (instr_i[15:13] == 3'b010) iff (instr_i[1:0] == 2'b00);
    C0_FLW  :  coverpoint (instr_i[15:13] == 3'b011) iff (instr_i[1:0] == 2'b00);
    C0_SW   :  coverpoint (instr_i[15:13] == 3'b110) iff (instr_i[1:0] == 2'b00);
    C0_FSW  :  coverpoint (instr_i[15:13] == 3'b111) iff (instr_i[1:0] == 2'b00);

    C1_ADDI      :  coverpoint (instr_i[15:13] == 3'b000)   iff ( instr_i[1:0] == 2'b01);
    C1_JAL       :  coverpoint (instr_i[15:13] == 3'b001)   iff ( instr_i[1:0] == 2'b01);
    C1_J         :  coverpoint (instr_i[15:13] == 3'b101)   iff ( instr_i[1:0] == 2'b01);
    C1_LI        :  coverpoint (instr_i[15:13] == 3'b010)   iff ( instr_i[1:0] == 2'b01);
    C1_LUI       :  coverpoint ((instr_i[15:13] == 3'b011)  && 
                  (!({instr_i[12], instr_i[6:2]} == 6'b0))) iff ( instr_i[1:0] == 2'b01);
    C1_ADDI16SP  :  coverpoint ((instr_i[15:13] == 3'b011)  && 
                                 (instr_i[11:7] == 5'h02)   &&
                  (!({instr_i[12], instr_i[6:2]} == 6'b0))) iff ( instr_i[1:0] == 2'b01);
    C1_SRLI      :  coverpoint ((instr_i[15:13] == 3'b100)  && 
                               (instr_i[11:10] == 2'b00)    &&
                               (!(instr_i[12] == 1'b1)))    iff ( instr_i [1:0] == 2'b01);
    C1_SRAI      :  coverpoint ((instr_i[15:13] == 3'b100)  && 
                               (instr_i[11:10] == 2'b01)    &&
                               (!(instr_i[12] == 1'b1)))    iff ( instr_i [1:0] == 2'b01);
    C1_ADD_I     :  coverpoint ((instr_i[15:13] == 3'b100)  && 
                               (instr_i[11:10] == 2'b10))   iff ( instr_i [1:0] == 2'b01);
    C1_SUB       :  coverpoint ((instr_i[15:13] == 3'b100)  && 
                               (instr_i[11:10] == 2'b11)    &&
                  (({instr_i[12], instr_i[6:5]})==3'b000))  iff ( instr_i [1:0] == 2'b01);
    C1_XOR       :  coverpoint ((instr_i[15:13] == 3'b100)  && 
                               (instr_i[11:10] == 2'b11)    &&
                  (({instr_i[12], instr_i[6:5]})==3'b001))  iff ( instr_i [1:0] == 2'b01);
    C1_OR        :  coverpoint ((instr_i[15:13] == 3'b100)  && 
                               (instr_i[11:10] == 2'b11)    &&
                  (({instr_i[12], instr_i[6:5]})==3'b010))  iff ( instr_i [1:0] == 2'b01);
    C1_AND       :  coverpoint ((instr_i[15:13] == 3'b100)  && 
                               (instr_i[11:10] == 2'b11)    &&
                  (({instr_i[12], instr_i[6:5]})==3'b011))  iff ( instr_i [1:0] == 2'b01);
    C1_BEQZ_BNEZ :  coverpoint ((instr_i[15:13] == 3'b110)  ||  (instr_i[15:13] == 3'b111)) 
                                                            iff ( instr_i [1:0] == 2'b01);
    
    C2_SLLI      :  coverpoint ((instr_i[15:13] == 3'b000)  &&  (!(instr_i[12] == 1'b1))) 
                                                            iff ( instr_i [1:0] == 2'b10);
    C2_LWSP      :  coverpoint ((instr_i[15:13] == 3'b010)  &&  (!(instr_i[11:7] == 5'b0))) 
                                                            iff ( instr_i [1:0] == 2'b10);
    C2_FLWSP     :  coverpoint (instr_i[15:13] == 3'b011)   iff ( instr_i [1:0] == 2'b10);
    C2_MV        :  coverpoint ((instr_i[15:13] == 3'b100)  &&
                                     (instr_i[12] == 1'b0)  &&
                                   (instr_i[6:2] != 5'b0))  iff ( instr_i [1:0] == 2'b10);
    C2_JR        :  coverpoint ((instr_i[15:13] == 3'b100)  &&
                                     (instr_i[12] == 1'b0)  &&
                                 (!(instr_i[6:2] != 5'b0))  &&
                               (!(instr_i[11:7] == 5'b0)))  iff ( instr_i [1:0] == 2'b10);
    C2_ADD       :  coverpoint ((instr_i[15:13] == 3'b100)  &&
                                  (!(instr_i[12] == 1'b0))  &&
                                   (instr_i[6:2] != 5'b0))  iff ( instr_i [1:0] == 2'b10);
    C2_EBREAK    :  coverpoint ((instr_i[15:13] == 3'b100)  &&
                                  (!(instr_i[12] == 1'b0))  &&
                                 (!(instr_i[6:2] != 5'b0))  &&
                                  (instr_i[11:7] == 5'b0))  iff ( instr_i [1:0] == 2'b10);
    C2_JALR      :  coverpoint ((instr_i[15:13] == 3'b100)  &&
                                  (!(instr_i[12] == 1'b0))  &&
                                 (!(instr_i[6:2] != 5'b0))  &&
                               (!(instr_i[11:7] == 5'b0)))  iff ( instr_i [1:0] == 2'b10);
    C2_SWSP      :  coverpoint  (instr_i[15:13] == 3'b110)  iff ( instr_i [1:0] == 2'b10);
    C2_FSWSP     :  coverpoint  (instr_i[15:13] == 3'b111)  iff ( instr_i [1:0] == 2'b10);
  endgroup : compressed_instruction_cg
  
  // Declaration of cover-groups
  compressed_instruction_cg compressed_instruction_cg_h;

  initial begin
    compressed_instruction_cg_h = new();       // Insatnce of a floating point status flags
  end

  `endif  // AZADI_FC

endmodule
