// cdp1802.v
// (c) 2014-2017 David R. Hunter
//
// Version History
// 06/29/14	- Finished version working on Cyclone I and II
// 03/25/15	- Removed loader module and modified IDLE state to work like 
//					the original 1802 design
// 04/26/15 - fixed cycle count to use modes rather than clr_n and wait_n
//          	suppress TPA during idle
// 04/29/15	- modify state machine to handle load address increment correctly
// 01/31/16	- change the state machine again to better match data sheet
// 08/17/17 - fixed carry/borrow and subtract bugs in ALU

// This is the upper level module for a CDP1802 processor
// the design is meant to match the operation and timing of an
// RCA CDP1802 as close as possible. 
// The modules are:
//      cdp1802         - main module
//      datapath        - registers and data paths for the processor
//      registers       - 16 x 16bit scratch pad registers
//      alu             - ALU for math, logic and shift operations

// The data bus is separated into data_in and data_out
// there is an output enable (oe_n) that can be used with an external
// tri-state buffer to provide bi-direction I/O

// The signal 'ma1' is the upper byte of the address register
// which can be used with 'ma' to give a 16 bit address so an external
// latch is not needed.  Note that ma still has both address bytes
// so that true 1802 operation is possible using an external latch.

// The signal 'cycle_out' indicates the machine cycle and is used for
// debugging and simulating.  It can be left unconnected.

// The other signal lines match those of the CDP1802.

// This design is based on data sheets and other documentation.
// It is dedicated to the CDP1802 designer Joe Weisbecker.


module cdp1802new(clk,clr_n,wait_n,dmai_n,dmao_n,int_n,ef1_n,ef2_n,ef3_n,ef4_n,
    data_in,xtal_n,tpa,tpb,mwr_n,mrd_n,sc,q,n_out,data_out,ma,    
    ma1,oe_n,cycle_out);
    
    // input control signals
  input clk,clr_n,wait_n;			// control inputs [~CLOCK,~CLEAR,~WAIT]
  input dmai_n,dmao_n,int_n;		// external requests [~DMA IN,~DMA OUT,~INT]
  input ef1_n,ef2_n,ef3_n,ef4_n;    // external flags [~EF1 to ~EF4]
    // input data
  input [7:0]data_in;				// data bus in
    // output control signals
  output xtal_n;						// inverted clock out [~XTAL]
  output tpa,tpb,mwr_n,mrd_n;		// memory cycle outputs [TPA,TPB,~MWR,~MRD]
  output [1:0]sc;						// state code [SC]
    // outputs
  output q;								// q flip flop [Q]
  output [2:0]n_out;					// I/O command outputs [N2,N1,N0]
  output [7:0]data_out;				// data bus out
  output [7:0]ma;						// mux address output [MA]
  
    // outputs not in the original design
  output [7:0]ma1;					// upper address byte
  output oe_n;        // output enable for an external tri-state buffer
    // debug signals
  output [2:0]cycle_out;			// machine clock cycle
  
  // registers that correspond to outputs
  reg tpa_r,tpb_r;      			// timing pulses
  reg mwr_n_r,mrd_n_r;  			// write and read signals
  reg q_r;              			// q flip flop output
  reg [2:0]nout_r;      			// I/O command outputs
  wire [7:0]dout_r;     			// output bus
  wire [7:0]ma_r;       			// memory address output (mux)
  wire [7:0]ma1_r;      			// memory address upper byte
  reg [1:0]sc_r;        			// state code
  
  // latched external flags (EF)
  reg [3:0]ef_in;
  
  // latched DMA inputs
  reg dma_in;
  reg dma_out;

  // latched interrupt input
  reg int_in;   
  
  // control and timing signal outputs
  wire [9:0]clocks;      // clocks to datapath registers
  wire [15:0]selects;    // selects to datapath muxes
  
    // data path clocks
  reg aclk;
  reg bclk;
  reg dclk;
  reg inclk;
  reg pclk;
  reg tclk;
  reg xclk;
  reg rwr0;
  reg rwr1;

  assign clocks = {rwr1,rwr0,xclk,tclk,pclk,inclk,dclk,bclk,aclk};

    // data path selects    
  reg asel;
  reg [1:0]dsel;
  reg [1:0]psel;
  reg [1:0]xsel;
  reg [1:0]bussel;
  reg [2:0]rinsel;
  reg [2:0]regsel;

  assign selects = {1'b0,regsel,rinsel,bussel,xsel,psel,dsel,asel};
 
  // internal registers and signals
  reg  power_up = 1'b0;    	// power up signal to act as a power on reset
  reg  [2:0]cycle = 3'b000;	// clock cycle (8 clocks / machine cycle)
  reg  [2:0]state = 3'b000;	// state values
  reg  [2:0]next;   	// next state
  reg  forceS1;     	// force another S1 (execute) cycle
  reg  idle;        	// idle flag
  reg  int_en;      	// interrupt enable
  reg  read_en;     	// enable a read cycle
  reg  write_en;    	// enable a write cycle
  reg  output_en;   	// signal cpu bus output

  reg  [1:0]mode;   	// CPU mode based on clear and wait inputs
  wire cycle0;      	// cycle 0 pulse
  wire dma;         	// dma flag
  wire intrpt;      	// intrpt flag
  
  wire [3:0]i;      	// I register value
  wire [3:0]n;      	// N register value
  wire zf;          	// zero flag
  wire df;          	// data flag
  wire lf;				       // load flag for data path
  
  // define the modes
  // modes = (CLR,WAIT)
  parameter LOAD        = 2'b00;
  parameter RESET       = 2'b01;
  parameter PAUSE       = 2'b10;
  parameter RUN         = 2'b11;
  
  // define the states of the master state machine
  parameter S1_RESET    = 3'b000;
  parameter S1_INIT     = 3'b001;
  parameter S0_FETCH    = 3'b010;
  parameter S1_EXEC     = 3'b011;
  parameter S2_DMA      = 3'b100;
  parameter S3_INT      = 3'b101;
  parameter S1_LOAD		= 3'b110;
  
  // assign output signals
  assign xtal_n = ~clk;     // invert the clock for the xtal output
  assign q = q_r;
  assign n_out = nout_r;
  assign data_out = dout_r;
  assign ma1 = ma1_r;
  assign oe_n = ~output_en;
  assign cycle_out = cycle;

  // multiplex with the loader module
  assign tpa = tpa_r;
  assign tpb = tpb_r;
  assign sc = sc_r;
  assign ma = ma_r;
							// read deasserts at the beginning of cycle 0
							// so 'or'-ing with cycle0 will do that
  assign mrd_n = (mrd_n_r | cycle0);
  assign mwr_n = mwr_n_r;
  
  // internal assignments
  assign intrpt = (int_in && int_en);
  assign dma = (dma_in || dma_out);
  assign lf = (state == S1_LOAD);
  
  // handle the power up signal, initialized to 0 when configured
  always @(posedge clk)
  begin
		if (!power_up)
			power_up <= 1'b1; 
  end
  
  // synchronize the mode with the falling edge of the clock
  always @(negedge clk)
  begin
    mode <= { clr_n, wait_n };
  end
  
  //*** machine cycle counter
    
  // set the cycle count
  // there are 8 clocks per machine cycle
  // hold the cycle if in PAUSE
  always @(negedge clk)
	begin
		if (mode == RESET)
			cycle <= 3'b111;
		else if ((mode != PAUSE) && (cycle == 3'b111))
			cycle <= 3'b000;
		else if ((mode != PAUSE) && (cycle != 3'b111))
			cycle <= cycle + 3'b001;
	end
  
  assign cycle0 = (cycle == 3'b000);	// indicate start of machine cycle
  
  //*** master state machine
  
  // set state at the start of a machine cycle
  always @(negedge clk)
	begin
	  if (mode == RESET)
	    state <= S1_RESET;
		else if ((cycle == 3'b111) && (mode != PAUSE))
			state <= next;
	end

  // determine the next state
  // if power up or re-entering a reset, restart the state machine
  always @(power_up or mode or state or idle or dma or intrpt or forceS1)
	begin
	if (!power_up) 
		next <= S1_RESET;
	else
		case (state)
			S1_RESET:   
				next <= S1_INIT;
		    
			S1_INIT:
				if (mode == LOAD)    // go straight to load to not increment R0
				  next <= S1_LOAD;
				else if (dma)	            // go to DMA directly if not in load
					next <= S2_DMA;
				else
					next <= S0_FETCH;
			    
			S0_FETCH:
				if (mode == LOAD)		// do an initial read (i.e. fetch) before load state
					next <= S1_LOAD;
				else
					next <= S1_EXEC;
			
			S1_EXEC:
				if (forceS1)
					next <= S1_EXEC;
				else if (dma)
					next <= S2_DMA;
				else if (intrpt)
					next <= S3_INT;
				else if (idle)
					next <= S1_EXEC;
				else
					next <= S0_FETCH;
			    
			S2_DMA:
				if (dma)
					next <= S2_DMA;
				else if (intrpt)
					next <= S3_INT;
				else if (mode == LOAD)
					next <= S1_LOAD;
				else
					next <= S0_FETCH;
			    
			S3_INT:
				if (dma)
					next <= S2_DMA;
				else
					next <= S0_FETCH;

			S1_LOAD:
				if (dma)
					next <= S2_DMA;
				else
					next <= S1_LOAD;
		
			default:                // just in case, go back to reset
				next <= S1_RESET;
			endcase
    end

`ifdef SIM  
  // state display
  always @(posedge clk)
    begin
		if (cycle0)
        case (state)
            S1_RESET:   $display("*** S1_RESET ***");
            S1_INIT:    $display("*** S1_INIT ***");
            S0_FETCH:   $display("*** S0_FETCH ***");
            S1_EXEC:    $display("*** S1_EXEC ***");
            S2_DMA:     $display("*** S2_DMA ***");
            S3_INT:     $display("*** S3_INT ***");
				S1_LOAD:		$display("*** S1_LOAD ***");
        endcase
    end
`endif 

	 
  // set the state codes
  always @(state)
    begin
        if (state == S0_FETCH)
            sc_r <= 2'b00;
        else if (state == S2_DMA)
            sc_r <= 2'b10;
        else if (state == S3_INT)
            sc_r <= 2'b11;
        else
            sc_r <= 2'b01;
    end

  //*** TIMING SECTION
  
  // handle the timing pulses
  // suppress TPA in load
  always @(cycle or state)
    begin
        if ((cycle == 3'b001) && (state != S1_LOAD))
            tpa_r <= 1;
        else
            tpa_r <= 0;
    end
    
  always @(posedge clk)
    begin
        if (cycle == 3'b110)
            tpb_r <= 1;
        else
            tpb_r <= 0;
    end
    
  // handle read and write cycles
  always @(posedge clk)
    begin
        if (state == S1_LOAD) // hold read during load
            mrd_n_r <= 0;
        else if (cycle0) 
              mrd_n_r <= 1;
        else if (read_en && (cycle > 3'b000))
            mrd_n_r <= 0;
        else
            mrd_n_r <= 1;
    end
  
  always @(cycle or write_en)
    begin
        if (write_en && ((cycle == 3'b101) || (cycle == 3'b110)))
            mwr_n_r <= 0;
        else
            mwr_n_r <= 1;
    end
    
  // DMA SAMPLING
  always @(negedge clk)
    begin
        if (tpb_r && ((state == S1_EXEC) || (state == S2_DMA) ||
                (state == S3_INT) || (state == S1_LOAD)))
          begin
            dma_in <= ~dmai_n;
            dma_out <= ~dmao_n;
          end
    end
  
  // EF SAMPLING
  always @(posedge clk)
    begin
        if (cycle == 3'b001)
            ef_in <= {!ef4_n, !ef3_n, !ef2_n, !ef1_n};
    end

  // INTERRUPT SAMPLING
  always @(negedge clk)
    begin
        if (tpb_r)
            int_in <= !int_n;
    end
  

  //*** CONTROL SECTION
  
  // memory cycles are based on the 1982 RCA Data book (SSD-260A) pgs.32 & 33
  // No. 1 = fetch, non-memory
  // No. 2 = fetch, memory write
  // No. 3 = fetch, memory read
  // No. 4 = fetch, memory read, memory read (long branch/skip)
  // No. 5 = fetch, input cycle
  // No. 6 = fetch, output cycle
  // No. 7 = DMA IN
  // No. 8 = DMA OUT
  // No. 9 = INTERRUPT
  
  // handle write enables (memory cycles 2,5 and 7)
  always @(state or i or n or dma_in)
    begin
        // STR (0x5X)
        if ((state == S1_EXEC) && (i == 4'b0101))
            write_en <= 1;
        // DATA IN (0x69 - 0x6F)
        else if ((state == S1_EXEC) && (i == 4'b0110) && n[3] &&
                    (n[2:0] != 3'b000))                                        
            write_en <= 1;
        // STXD (0x73)
        else if ((state == S1_EXEC) && (i == 4'b0111) && (n == 4'b0011))
            write_en <= 1;
        // SAV (0x78), MARK (0x79)
        else if ((state == S1_EXEC) && (i == 4'b0111) && (n[3:1] == 3'b100))
            write_en <= 1;
        else if ((state == S2_DMA) && (dma_in))
            write_en <= 1;
        else
            write_en <= 0;
    end
    
  // handle read enables (memory cycles 3,4,6 and 8)
  always @(state or i or n or dma_out)
    begin
        // memory fetch
        if (state == S0_FETCH)
            read_en <= 1;
        // LDN (0x0X)
        else if ((state == S1_EXEC) && (i == 4'b0000) && (n != 4'b0000))
            read_en <= 1;
        // BR (0x3X)
        else if ((state == S1_EXEC) && (i == 4'b0011))
            read_en <= 1;
        // LDA (0x4X)
        else if ((state == S1_EXEC) && (i == 4'b0100))
            read_en <= 1;
        // DATA OUT (0x61 - 0x67)
        else if ((state == S1_EXEC) && (i == 4'b0110) && !n[3] && 
                    (n[2:0] != 3'b000))                                        
            read_en <= 1;
        // Misc (0x7X)
        else if ((state == S1_EXEC) && (i == 4'b0111))
            case (n)
                4'b0000:    read_en <= 1;
                4'b0001:    read_en <= 1;
                4'b0010:    read_en <= 1;
                4'b0011:    read_en <= 0;
                4'b0100:    read_en <= 1;
                4'b0101:    read_en <= 1;
                4'b0110:    read_en <= 0;
                4'b0111:    read_en <= 1;
                4'b1000:    read_en <= 0;
                4'b1001:    read_en <= 0;
                4'b1010:    read_en <= 0;
                4'b1011:    read_en <= 0;
                4'b1100:    read_en <= 1;
                4'b1101:    read_en <= 1;
                4'b1110:    read_en <= 0;
                4'b1111:    read_en <= 1;
            endcase
        // LBR,LSKP,NOP (0xCX)
        else if ((state == S1_EXEC) && (i == 4'b1100))
            read_en <= 1;
        // ALU ops except SHR,SHL
        else if ((state == S1_EXEC) && (i == 4'b1111) && (n[2:0] != 3'b110))                                        
            read_en <= 1;
        else if ((state == S2_DMA) && (dma_out))
            read_en <= 1;
		  else if (state == S1_LOAD)		// enable reads when in load
				read_en <= 1;
        else
            read_en <= 0;
    end
    
  // handle output enable
  // same as write_en except during I/O operations
  always @(state or i or write_en)
    begin
        if ((state == S1_EXEC) && (i != 4'b0110) && (write_en))
            output_en <= 1;
        else
            output_en <= 0;
    end


  // DATAPATH CLOCKS
  
  // handle the address register clock
  always @(posedge clk)
    begin
        if (cycle0)
            aclk <= 1;      // clock 1/2 cycle in
        else
            aclk <= 0;
    end
  
  // handle the B register clock
  always @(posedge clk)
    begin
        if (cycle == 3'b111)
          begin
            // LBR (0xC0-0xC3,0xC8-0xCB)
            // clock the first byte into the B register
            if ((state == S1_EXEC) && (i == 4'b1100) && !n[2] && forceS1)
                bclk <= 1;
            else
                bclk <= 0;
          end
        else
            bclk <= 0;
    end
  
  // handle the D register clock
  always @(posedge clk)
    begin
        if (cycle == 3'b111)
          begin
            if (state == S1_EXEC)
              case (i)
                4'b0000:
                            if (n != 4'b0000)
                                dclk <= 1;      // LDN
                            else
                                dclk <= 0;		// IDL
                4'b0001:    dclk <= 0;
                4'b0010:    dclk <= 0;
                4'b0011:    dclk <= 0;
                4'b0100:    dclk <= 1;  			// LDA
                4'b0101:    dclk <= 0;
                4'b0110:
                            if (n[3] && (n[2:0] != 3'b000))
                                dclk <= 1;      // INPUT
                            else
                                dclk <= 0;
                4'b0111:
                            if (n == 4'b0010)
                                dclk <= 1;      // LDXA
                            else if (n[2])
                                dclk <= 1;  // ADC(I),SDB(I),SHRC,SHLC,SMB(I)
                            else
                                dclk <= 0;
                4'b1000:    dclk <= 1;      		// GLO
                4'b1001:    dclk <= 1;      		// GHI
                4'b1010:    dclk <= 0;
                4'b1011:    dclk <= 0;
                4'b1100:    dclk <= 0;
                4'b1101:    dclk <= 0;
                4'b1110:    dclk <= 0;
                4'b1111:    dclk <= 1;      		// ALU operations
              endcase
            else
                dclk <= 0;
          end
        else
            dclk <= 0;
    end
  
  // handle the I/N register clock
  always @(posedge clk)
    begin
        if ((cycle == 3'b111) && (state == S0_FETCH))
            inclk <= 1;
        else
            inclk <= 0;
    end
  
  // handle the P register clock
  always @(posedge clk)
    begin
        if (cycle == 3'b111)
          begin
            // RET or DIS (0x70 or 0x71)
            if ((state == S1_EXEC) && (i == 4'b0111) && (n[3:1] == 3'b000))
              begin
                pclk <= 1;
              end
            // SEP (0xDX)
            else if ((state == S1_EXEC) && (i == 4'b1101))
                pclk <= 1;
            // interrupt
            else if (state == S3_INT)
                pclk <= 1;
            else
                pclk <= 0;
          end
        else
            pclk <= 0;
    end
  
  // handle the T register clock
  always @(posedge clk)
    begin
        if (cycle == 3'b110)    // handle T one clock earlier
          begin
            // MARK (0x79)
            if ((state == S1_EXEC) && (i == 4'b0111) && (n == 4'b1001))
                tclk <= 1;
            // interrupt
            else if (state == S3_INT)
                tclk <= 1;
            else
                tclk <= 0;
          end
        else
            tclk <= 0;
    end
  
  // handle the X register clock
  always @(posedge clk)
    begin
        if (cycle == 3'b111)
          begin
            // RET or DIS (0x70 or 0x71)
            if ((state == S1_EXEC) && (i == 4'b0111) && (n[3:1] == 3'b000))
              begin
                xclk <= 1;
              end
            // MARK (0x79)
            else if ((state == S1_EXEC) && (i == 4'b0111) && (n == 4'b1001))
                xclk <= 1;
            // SEX (0xEX)
            else if ((state == S1_EXEC) && (i == 4'b1110))
                xclk <= 1;
            // interrupt
            else if (state == S3_INT)
                xclk <= 1;
            else
                xclk <= 0;
          end
        else
            xclk <= 0;
    end
  
  // handle the scratchpad register write clocks
  always @(posedge clk)
    begin
        if (cycle == 3'b111)
          begin
            if (state == S0_FETCH)
              begin
                rwr0 <= 1;
                rwr1 <= 1;
              end
            else if (state == S1_RESET)      // init R0
              begin
                rwr0 <= 1;
                rwr1 <= 1;
              end
            else if (state == S1_INIT)      // init R0
              begin
                rwr0 <= 1;
                rwr1 <= 1;
              end
            else if (state == S1_EXEC)
              case (i)
                4'b0000:
                    begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                    end
                4'b0001:    // INC N
                    begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                    end
                4'b0010:    // DEC N
                    begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                    end
                4'b0011:    // BR
                    if (n == 4'b1000)   // NBR
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0010) && (!zf)) // BZ fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1010) && (zf))  // BNZ fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0011) && (!df)) // BDF fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1011) && (df))  // BNF fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0001) && (!q)) // BQ fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1001) && (q))  // BNQ fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0100) && (!ef_in[0])) // B1 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1100) && (ef_in[0]))  // BN1 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0101) && (!ef_in[1])) // B2 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1101) && (ef_in[1]))  // BN2 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0110) && (!ef_in[2])) // B3 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1110) && (ef_in[2]))  // BN3 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0111) && (!ef_in[3])) // B4 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1111) && (ef_in[3]))  // BN4 fails
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else
                      begin
                        rwr0 <= 1;      // new RP if succeeds
                        rwr1 <= 0;
                      end
                4'b0100:    // LDA
                    begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                    end
                4'b0101:
                    begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                    end
                4'b0110:    // IRX, OUT N
                    if (!n[3])
                        begin
                            rwr0 <= 1;
                            rwr1 <= 1;
                        end
                    else
                        begin
                            rwr0 <= 0;
                            rwr1 <= 0;
                        end
                4'b0111:
                    if (n[3:2] == 2'b00)    // 0x70-0x73
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b1001)  // 0x79
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                                                // 0x7C,0x7D,0x7F
                    else if ((n[3:2] == 2'b11) && (n[1:0] != 2'b10))  
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                4'b1000:
                    begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                    end
                4'b1001:
                    begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                    end
                4'b1010:    // PLO
                    begin
                        rwr0 <= 1;
                        rwr1 <= 0;
                    end
                4'b1011:    // PHI
                    begin
                        rwr0 <= 0;
                        rwr1 <= 1;
                    end
                4'b1100:    // LBR
                    if (n == 4'b1000)   // NLBR
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b0010) // LBZ 
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b1010)  // LBNZ
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b0011) // LBDF
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b1011)  // LBNF
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b0001) // LBQ
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b1001)  // LBNQ 
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if (n == 4'b0100)  // NOP
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end                    
                    else if ((n == 4'b1110) && (zf)) // LSZ
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1110) && (!zf)) // LSZ fails
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                    else if ((n == 4'b0110) && (!zf))  // LSNZ
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0110) && (zf))  // LSNZ fails
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                    else if ((n == 4'b1111) && (df)) // LSDF
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1111) && (!df)) // LSDF fails
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                    else if ((n == 4'b0111) && (!df))  // LSNF
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0111) && (df))  // LSNF fails
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                    else if ((n == 4'b1101) && (q)) // LSQ
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1101) && (!q)) // LSQ fails
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                    else if ((n == 4'b0101) && (!q))  // LSNQ
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b0101) && (q))  // LSNQ fails
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                    else if ((n == 4'b1100) && (int_en))  // LSIE
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                    else if ((n == 4'b1100) && (!int_en))  // LSIE fails
                      begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                      end
                    else
                      begin
                        rwr0 <= 1;
                        rwr1 <= 1;
                      end
                4'b1101:
                    begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                    end
                4'b1110:
                    begin
                        rwr0 <= 0;
                        rwr1 <= 0;
                    end
                4'b1111:  // ALU Immediate instructions
                    if ((n[3]) && (n[2:0] != 3'b110))
                        begin
                            rwr0 <= 1;
                            rwr1 <= 1;
                        end
                    else
                        begin
                            rwr0 <= 0;
                            rwr1 <= 0;
                        end
              endcase
            else if (state == S2_DMA)  // increment R0
              begin
                rwr0 <= 1;
                rwr1 <= 1;
              end
            else
              begin
                rwr0 <= 0;
                rwr1 <= 0;
              end
          end
        else
          begin
            rwr0 <= 0;
            rwr1 <= 0;
          end
    end

  // DATAPATH MUX SELECTS
  
  // handle D register input
  always @(state or i or n)
    begin
        if (state == S1_EXEC)
          case (i)
            4'b0000:    dsel <= 2'b00;  		// LDN
            4'b0001:    dsel <= 2'b00;
            4'b0010:    dsel <= 2'b00;
            4'b0011:    dsel <= 2'b00;
            4'b0100:    dsel <= 2'b00;  		// LDA
            4'b0101:    dsel <= 2'b00;
            4'b0110:    dsel <= 2'b00;
            4'b0111:
                    if (n[2])
                        dsel <= 2'b01;      // ALU operations
                    else
                        dsel <= 2'b00;
            4'b1000:    dsel <= 2'b10;      // GLO
            4'b1001:    dsel <= 2'b11;      // GHI
            4'b1010:    dsel <= 2'b00;
            4'b1011:    dsel <= 2'b00;
            4'b1100:    dsel <= 2'b00;
            4'b1101:    dsel <= 2'b00;
            4'b1110:    dsel <= 2'b00;
            4'b1111:
                    if (n[2:0] != 3'b000)
                        dsel <= 2'b01;      // ALU operations
                    else
                        dsel <= 2'b00;      // LDX,LDI operations
          endcase
        else
            dsel <= 2'b00;
    end

  // handle P register input
  always @(state or i)
    begin
        if (state == S1_EXEC)
          if (i == 4'b1101)         // SET P
            psel <= 2'b10;          // N reg
          else
            psel <= 2'b00;          // DIN [3:0]
        else if (state == S3_INT)
            psel <= 2'b01;          // force P=1 on interrupt
        else
            psel <= 2'b11;          // set to 0
    end

  // handle X register input
  always @(state or i or n)
    begin
        if (state == S1_EXEC)
          begin
              if (i == 4'b1110)         // SET X
                xsel <= 2'b10;          // N reg
              else if ((i == 4'b0111) && (n == 4'b1001))
                xsel <= 2'b11;          // set to P (MARK 0x79)
              else
                xsel <= 2'b00;          // DIN [7:4] (RET or DIS)
          end
        else if (state == S3_INT)
            xsel <= 2'b01;          // force X=2 on interrupt
		  else
		      xsel <= 2'b00;				// don't care state
    end

  // handle data output mux
  always @(state or i or n)
    begin
        if (state == S1_EXEC)
          case (i)
            4'b0000:    bussel <= 2'b00;
            4'b0001:    bussel <= 2'b00;
            4'b0010:    bussel <= 2'b00;
            4'b0011:    bussel <= 2'b00;
            4'b0100:    bussel <= 2'b00;
            4'b0101:    bussel <= 2'b01;    // STR (D->bus)
            4'b0110:    bussel <= 2'b00;
            4'b0111:    
                    if (n == 4'b0011)       // STXD
                        bussel <= 2'b01;    // D->bus
                    else if (n == 4'b1000)  // SAV
                        bussel <= 2'b10;    // T->bus
                    else if (n == 4'b1001)  // MARK
                        bussel <= 2'b11;    // {X:P}->bus
                    else
                        bussel <= 2'b00;
                        
            4'b1000:    bussel <= 2'b00;
            4'b1001:    bussel <= 2'b00;
            4'b1010:    bussel <= 2'b01;
            4'b1011:    bussel <= 2'b01;
            4'b1100:    bussel <= 2'b00;
            4'b1101:    bussel <= 2'b00;
            4'b1110:    bussel <= 2'b00;
            4'b1111:    bussel <= 2'b00;
          endcase
        else
            bussel <= 2'b00;
    end

  // handle register input mux
  always @(state or i or n or forceS1 or zf or df or q_r or ef_in)
    begin
        if (state == S0_FETCH)
            rinsel <= 3'b011;               // INC
        else if (state == S1_EXEC)
          case (i)
            4'b0000:    rinsel <= 3'b000;
            4'b0001:    rinsel <= 3'b011;   // INC
            4'b0010:    rinsel <= 3'b100;   // DEC
            4'b0011:                        // short branches
                    if (n == 4'b0000)
                        rinsel <= 3'b001;   // BR
                    else if ((n == 4'b0010) && (zf))    // BZ
                        rinsel <= 3'b001;
                    else if ((n == 4'b1010) && (!zf))   // BNZ
                        rinsel <= 3'b001;
                    else if ((n == 4'b0011) && (df))    // BDF
                        rinsel <= 3'b001;
                    else if ((n == 4'b1011) && (!df))   // BNF
                        rinsel <= 3'b001;
                    else if ((n == 4'b0001) && (q_r))    // BQ
                        rinsel <= 3'b001;
                    else if ((n == 4'b1001) && (!q_r))   // BNQ
                        rinsel <= 3'b001;
                    else if ((n == 4'b0100) && (ef_in[0])) // B1
                        rinsel <= 3'b001;
                    else if ((n == 4'b1100) && (!ef_in[0]))   // BN1
                        rinsel <= 3'b001;
                    else if ((n == 4'b0101) && (ef_in[1])) // B2
                        rinsel <= 3'b001;
                    else if ((n == 4'b1101) && (!ef_in[1]))   // BN2
                        rinsel <= 3'b001;
                    else if ((n == 4'b0110) && (ef_in[2])) // B3
                        rinsel <= 3'b001;
                    else if ((n == 4'b1110) && (!ef_in[2]))   // BN3
                        rinsel <= 3'b001;
                    else if ((n == 4'b0111) && (ef_in[3])) // B4
                        rinsel <= 3'b001;
                    else if ((n == 4'b1111) && (!ef_in[3]))   // BN4
                        rinsel <= 3'b001;
                    else
                        rinsel <= 3'b011;   // else, allow for an increment
                        
            4'b0100:    rinsel <= 3'b011;   // LDA
            4'b0101:    rinsel <= 3'b000;
            4'b0110:    rinsel <= 3'b011;   // I/O, IRX
            4'b0111:
                    if ((n == 4'b0011) || (n == 4'b1001))    // STXD or MARK
                        rinsel <= 3'b100;   // DEC
                    else
                        rinsel <= 3'b011;   // INC
                        
            4'b1000:    rinsel <= 3'b000;
            4'b1001:    rinsel <= 3'b000;
            4'b1010:    rinsel <= 3'b010;   // PLO
            4'b1011:    rinsel <= 3'b010;   // PHI
            4'b1100:                        // long branches
                    if (!forceS1)
                        if (n == 4'b0000)
                            rinsel <= 3'b101;   // LBR
                        else if ((n == 4'b0010) && (zf))    // LBZ
                            rinsel <= 3'b101;
                        else if ((n == 4'b1010) && (!zf))   // LBNZ
                            rinsel <= 3'b101;
                        else if ((n == 4'b0011) && (df))    // LBDF
                            rinsel <= 3'b101;
                        else if ((n == 4'b1011) && (!df))   // LBNF
                            rinsel <= 3'b101;
                        else if ((n == 4'b0001) && (q_r))    // LBQ
                            rinsel <= 3'b101;
                        else if ((n == 4'b1001) && (!q_r))   // LBNQ
                            rinsel <= 3'b101;
                        else
                            rinsel <= 3'b011;   // increment
                    else
                        rinsel <= 3'b011;   // else, allow for an increment
                        
            4'b1101:    rinsel <= 3'b000;
            4'b1110:    rinsel <= 3'b000;
            4'b1111:    rinsel <= 3'b011;   // ALU
          endcase
        else if (state == S2_DMA)
            rinsel <= 3'b011;               // increment for DMA
        else
            rinsel <= 3'b000;
    end

  // handle register address mux
  always @(state or i or n)
	begin
		if (state == S0_FETCH)
            regsel <= 3'b001;                // P->RA
		else if (state == S1_EXEC)
          case (i)
            4'b0000:    regsel <= 3'b010;    // LDN  N->RA, IDL
            4'b0001:    regsel <= 3'b010;    // INC  N->RA
            4'b0010:    regsel <= 3'b010;    // DEC  N->RA
            4'b0011:    regsel <= 3'b001;    // BR   P->RA
            4'b0100:    regsel <= 3'b010;    // LDA  N->RA
            4'b0101:    regsel <= 3'b010;    // STR  N->RA
            4'b0110:    regsel <= 3'b011;    // I/O  X->RA
            4'b0111:    
                    if (n[3:2] == 2'b11)
                        regsel <= 3'b001;    // Immediate P->RA
                    else if (n == 4'b1001)    // MARK  2->RA
                        regsel <= 3'b100; 
                    else
                        regsel <= 3'b011;    // Misc X->RA
                        
            4'b1000:    regsel <= 3'b010;    // GLO  N->RA
            4'b1001:    regsel <= 3'b010;    // GHI  N->RA
            4'b1010:    regsel <= 3'b010;    // PLO  N->RA
            4'b1011:    regsel <= 3'b010;    // PHI  N->RA
            4'b1100:    regsel <= 3'b001;    // LBR  P->RA
            4'b1101:    regsel <= 3'b010;    // SEP  N->RA    
            4'b1110:    regsel <= 3'b010;    // SEX  N->RA
            4'b1111:
                    if (n[3])
                        regsel <= 3'b001;    // ALU Immediate P->RA
                    else
                        regsel <= 3'b011;    // ALU  X->RA
          endcase
		else if (state == S2_DMA)           	// 0->RA
            regsel <= 3'b000;
		else if (state == S1_RESET)		       	// 0->RA
		        regsel <= 3'b000;
		else if (state == S1_INIT)		       	 // 0->RA
		        regsel <= 3'b000;
		else if (state == S1_LOAD)					      // 0->RA
				    regsel <= 3'b000;
		else
            regsel <= 3'b010;                // otherwise N->RA
    end
  

  // handle the address output mux
  always @(posedge clk)
    begin
        if (cycle0)
            asel <= 1;
        else if (cycle > 3'b001)
            asel <= 0;
        else
            asel <= 1;
    end

  // handle I/O output lines
  always @(state or clr_n or i or n)
    begin
        if (!clr_n)
            nout_r <= 3'b000;
        else if ((state == S1_EXEC) && (i == 4'b0110))
            nout_r <= n[2:0];
        else
            nout_r <= 3'b000;
    end
  
  // handle q
  always @(posedge clk)
    begin
        if (!clr_n)
            q_r <= 0;
            // Q transitions in cycle 3
                                            // REQ & SEQ (0x7A or 0x7B)
        else if ((state == S1_EXEC) && (cycle == 3'b011) && 
                    (i == 4'b0111) && (n[3:1] == 3'b101))
            q_r <= n[0];
    end


  // handle interrupt enable
  // change on same cycle as q (it's not documented)
  always @(posedge clk)
    begin
        if (!clr_n)
            int_en <= 1;            // interrupts enabled on reset
        else if ((state == S3_INT) && (cycle == 3'b011))
            int_en <= 0;            // disable after entering INT state
            
                                    // RET or DIS (0x70 or 0x71)
        else if ((state == S1_EXEC) && (cycle == 3'b011) && 
                (i == 4'b0111) && (n[3:1] == 3'b000))
				    int_en <= !n[0];
    end


  // handle forceS1
  // change during cycle 0 so it can be caught by the state machine
  always @(posedge clk)
    begin
        if (!clr_n)
            forceS1 <= 0;            // disable on reset
        else if (state == S0_FETCH)
            forceS1 <= 0;           // always reset on a fetch
        else if ((state == S1_EXEC) && (cycle0) && (i == 4'b1100))
		    begin
            if (!forceS1)
                forceS1 <= 1;
            else
                forceS1 <= 0;       // reset after the 1st exec cycle
			 end
    end

    
  // handle idle
  always @(posedge clk)
    begin
		if (mode == RESET)	// if reset
            idle <= 0;            // reset idle value
			// change on same cycle as q (it's not documented)
		else if ((state == S1_EXEC) && (cycle == 3'b011) && 
                    (i == 4'b0000) && (n == 4'b0000))   // IDL (0x00)
            idle <= 1;
      else if ((state == S2_DMA) || (state == S3_INT))
            idle <= 0;          // reset after DMA or interrupt
    end

  //*** DATAPATH MODULE
  datapath dp(clr_n,lf,data_in,clocks,selects,i,n,zf,df,dout_r,ma_r,ma1_r);

endmodule


// datapath.v
// 6/13/14  - D. Hunter
// 1/24/16	- add load mode input signal
// This handles the internal data paths of the CDP1802
// It uses the ALU and register modules

module datapath(clr_n,load,din,clocks,selects,i,n,zf,df,dout,ma,ma1);
    input clr_n;                // reset input
	  input load;					            // load state signal
    input [7:0]din;             // input data
    input [9:0]clocks;          // input clocks to various registers
    input [15:0]selects;        // input selects to various multiplexers
    output [3:0]i;              // I register value
    output [3:0]n;              // N register value
    output zf;                  // zero flag
    output df;                  // data flag
    output [7:0]dout;           // output data
    output [7:0]ma;             // memory address
    output [7:0]ma1;            // upper memory address (unmuxed)

    // ALU opcodes
    parameter OP_NOP = 4'b0000,
              OP_OR  = 4'b0001,
              OP_AND = 4'b0010,
              OP_XOR = 4'b0011,
              OP_ADD = 4'b0100,
              OP_SD  = 4'b0101,
              OP_SHR = 4'b0110,
              OP_SM  = 4'b0111,
              OP_SHL = 4'b1000,
              OP_SLC = 4'b1001,
              OP_ADC = 4'b1100,
              OP_SDB = 4'b1101,
              OP_SRC = 4'b1110,
              OP_SMB = 4'b1111;


    // clock signals
    wire aclk;                  	// address register clock
    wire bclk;                  	// B register clock
    wire dclk;                  	// D,DF register clock
    wire inclk;                 	// I,N register clock
    wire pclk;                  	// P register clock
    wire tclk;                  	// T register clock
    wire xclk;                  	// X register clock
    wire rwr0;                  	// register write 0 (low byte)
    wire rwr1;                  	// register write 1 (high byte)
    
    // selects
    wire asel;                  	// address mux select
    wire [1:0]dsel;             	// D register input select
    wire [1:0]psel;             	// P register input select
    wire [1:0]xsel;             	// X register input select
    wire [1:0]bussel;           	// Data out select
    wire [2:0]rinsel;           	// register input select
    wire [2:0]regsel;           	// register address select
    
    // internal registers
    reg  df_r;                   // data flag register
    reg  [7:0]ma_r;              // memory address output
    
    reg  [15:0]areg;             // address (A) register
    reg  [7:0]breg;              // B register
    reg  [7:0]dreg;              // D register
    reg  [7:0]treg;              // T register
    reg  [3:0]ireg;              // I register
    reg  [3:0]nreg;              // N register
    reg  [3:0]preg;              // P register
    reg  [3:0]xreg;              // X register
    
    // internal signals and mux outputs
    wire [15:0]increg;          	// increment register
    wire [15:0]decreg;          	// decrement register
    reg  [7:0]dmux;              // D register input mux
    reg  [3:0]pmux;              // P register input mux
    reg  [3:0]xmux;              // X register input mux
    reg  [7:0]dout_r;            // output data mux
    
    // scratchpad register signals
    reg  [3:0]reg_addr;          // register address mux
    reg  [7:0]reg_mux1;          // input mux high
    reg  [7:0]reg_mux0;          // input mux low
    wire [7:0]reg_out1;         	// output high
    wire [7:0]reg_out0;         	// output low
    
    // ALU signals
    reg 	[3:0]aluop;             // alu op code
    wire [7:0]alu_out;          	// ALU output
    wire cy;                    	// carry output
    
    // input assignments
    // mapping of the clocks input
    assign aclk = clocks[0];
    assign bclk = clocks[1];
    assign dclk = clocks[2];
    assign inclk = clocks[3];
    assign pclk = clocks[4];
    assign tclk = clocks[5];
    assign xclk = clocks[6];
    assign rwr0 = clocks[7];
    assign rwr1 = clocks[8];
    
    // mapping of the selects input
    assign asel = selects[0];
    assign dsel = selects[2:1];
    assign psel = selects[4:3];
    assign xsel = selects[6:5];
    assign bussel = selects[8:7];
    assign rinsel = selects[11:9];
    assign regsel = selects[14:12];
    
   
    // output assignments
    assign i = ireg;
    assign n = nreg;
    assign zf = (dreg == 8'h00);        // set zero flag
    assign df = df_r;
    assign dout = dout_r;
    assign ma = ma_r;
    assign ma1 = areg[15:8];
    
    //*** register muxes
    // D register input mux
    always @(dsel or din or alu_out or reg_out0 or reg_out1)
      begin
        case (dsel)
            2'b00:
                dmux <= din;
            
            2'b01:
                dmux <= alu_out;
                
            2'b10:
                dmux <= reg_out0;
                
            2'b11:
                dmux <= reg_out1;
        endcase
      end
    
    // P register input mux
    always @(psel or din or nreg)
      begin
        case (psel)
            2'b00:
                pmux <= din[3:0];
            
            2'b01:
                pmux <= 4'b0001;            // register 1
                
            2'b10:
                pmux <= nreg;
                
            2'b11:
                pmux <= 4'b0000;            // invalid state
        endcase
      end
    
    // X register input mux
    always @(xsel or din or nreg or preg)
      begin
        case (xsel)
            2'b00:
                xmux <= din[7:4];
            
            2'b01:
                xmux <= 4'b0010;            // register 2
                
            2'b10:
                xmux <= nreg;
            
            2'b11:
                xmux <= preg;            // for MARK (0x79) instruction
        endcase
      end
      
    // scratchpad register address mux
    always @(regsel or preg or nreg or xreg)
      begin
        case (regsel)
            3'b000:
                reg_addr <= 4'b0000;        // select register 0 for DMA
        
            3'b001:
                reg_addr <= preg;
                
            3'b010:
                reg_addr <= nreg;
                
            3'b011:
                reg_addr <= xreg;

            3'b100:
                reg_addr <= 4'b0010;    // select register 2 for MARK (0x79)

    default:
                reg_addr <= preg;

        endcase
      end
    
    // scratchpad register input mux
    always @(rinsel or din or dreg or increg or decreg or breg)
      begin
        case (rinsel)
            3'b000:                 // put zero on the input to clear register
              begin
                reg_mux1 <= 8'h00;
                reg_mux0 <= 8'h00;
              end
              
            3'b001:
              begin
                reg_mux1 <= din;
                reg_mux0 <= din;
              end
              
            3'b010:
              begin
                reg_mux1 <= dreg;
                reg_mux0 <= dreg;
              end

            3'b011:
              begin
                reg_mux1 <= increg[15:8];
                reg_mux0 <= increg[7:0];
              end

            3'b100:
              begin
                reg_mux1 <= decreg[15:8];
                reg_mux0 <= decreg[7:0];
              end
            
            3'b101:
              begin
                reg_mux1 <= breg;
                reg_mux0 <= din;
              end

            default:            // use all ones as an error condition
              begin
                reg_mux1 <= 8'hFF;
                reg_mux0 <= 8'hFF;
              end
        endcase
      end
      
    // DOUT mux
    always @(bussel or dreg or treg or xreg or preg)
      begin
        case (bussel)
            2'b00:
                dout_r <= 8'h00;
            
            2'b01:
                dout_r <= dreg;
                
            2'b10:
                dout_r <= treg;
                
            2'b11:
                dout_r <= {xreg , preg};
        endcase
      end
    
    // address mux
    always @(load or asel or areg or decreg)
      begin
			if (load)				    // output R0-1 to MA during load mode  
				    ma_r <= decreg[7:0];
			else if (asel)				// upper byte
            ma_r <= areg[15:8];
			else							// lower byte
            ma_r <= areg[7:0];
      end
  
    //*** register clocking
    // D,DF registers
    always @(posedge dclk or negedge clr_n)
      begin
        if (!clr_n)
          begin
            dreg <= 8'h00;          // clear D,DF on reset
            df_r <= 0;
          end
        else
          begin
            dreg <= dmux;
            df_r <= cy;
          end
      end
    
    // I/N registers
    always @(posedge inclk or negedge clr_n)
      begin
        if (!clr_n)
          begin
            ireg <= 4'b0000;        // clear I/N on reset
            nreg <= 4'b0000;
          end
        else
          begin
            ireg <= din[7:4];
            nreg <= din[3:0];
          end
      end
    
    // P register
    always @(posedge pclk or negedge clr_n)
      begin
        if (!clr_n)
            preg <= 4'b0000;
        else
            preg <= pmux;
      end
      
    // T register
    always @(posedge tclk)
      begin
        treg <= {xreg , preg};
      end
    
    // X register
    always @(posedge xclk or negedge clr_n)
      begin
        if (!clr_n)
            xreg <= 4'b0000;
        else
            xreg <= xmux;
      end
    
    // address register
    always @(posedge aclk)
      begin
        areg <= {reg_out1, reg_out0};
      end
    
    // increment and decrement registers
    assign increg = areg + 16'h0001;
    assign decreg = areg - 16'h0001;
    
    // B register
    always @(posedge bclk)
      begin
        breg <= din;
      end
    
    // ALU operation decoding using the ireg and nreg
    /* op code decoding is done here rather than passing I/N 
        to the control block only to have the op code come back here */
    always @(ireg or nreg)
      begin
        if (ireg == 4'b0111)
            case (nreg)
                4'b0000:
                    aluop <= OP_NOP;
                4'b0001:
                    aluop <= OP_NOP;
                4'b0010:
                    aluop <= OP_NOP;
                4'b0011:
                    aluop <= OP_NOP;
                4'b0100:
                    aluop <= OP_ADC;
                4'b0101:
                    aluop <= OP_SDB;
                4'b0110:
                    aluop <= OP_SRC;
                4'b0111:
                    aluop <= OP_SMB;
                4'b1000:
                    aluop <= OP_NOP;
                4'b1001:
                    aluop <= OP_NOP;
                4'b1010:
                    aluop <= OP_NOP;
                4'b1011:
                    aluop <= OP_NOP;
                4'b1100:
                    aluop <= OP_ADC;
                4'b1101:
                    aluop <= OP_SDB;
                4'b1110:
                    aluop <= OP_SLC;
                4'b1111:
                    aluop <= OP_SMB;
            endcase
        
        else if (ireg == 4'b1111)
            case (nreg)
                4'b0000:
                    aluop <= OP_NOP;
                4'b0001:
                    aluop <= OP_OR;
                4'b0010:
                    aluop <= OP_AND;
                4'b0011:
                    aluop <= OP_XOR;
                4'b0100:
                    aluop <= OP_ADD;
                4'b0101:
                    aluop <= OP_SD;
                4'b0110:
                    aluop <= OP_SHR;
                4'b0111:
                    aluop <= OP_SM;
                4'b1000:
                    aluop <= OP_NOP;
                4'b1001:
                    aluop <= OP_OR;
                4'b1010:
                    aluop <= OP_AND;
                4'b1011:
                    aluop <= OP_XOR;
                4'b1100:
                    aluop <= OP_ADD;
                4'b1101:
                    aluop <= OP_SD;
                4'b1110:
                    aluop <= OP_SHL;
                4'b1111:
                    aluop <= OP_SM;
            endcase
            
        else
            aluop <= OP_NOP;            // no op if not an ALU instruction
      end


    // 16 x 16 scratchpad registers
    registers ScratchPad(reg_addr, rwr1, rwr0, reg_mux1, reg_mux0,
        reg_out1, reg_out0);


    // ALU
    alu ALU(aluop,dreg,din,df_r,alu_out,cy);

endmodule


// registers.v
// D. Hunter   11/01/13
// note:  '1' = high byte,  '0' = low byte per 1802 notation

// define the registers module
module registers(sel, wr1, wr0, rin1, rin0, rout1, rout0);
    input [3:0]sel;             // register select
    input wr1, wr0;             // write lines
    input [7:0]rin1, rin0;      // register inputs 
    output [7:0]rout1, rout0;   // register outputs
    
    reg [7:0]scr1 [0:15];       // 16 upper byte scratch registers
    reg [7:0]scr0 [0:15];       // 16 lower byte scratch registers
	 
	 // clear registers for simulation
	 initial
	 begin
		scr1[0] = 8'h00;
		scr0[0] = 8'h00;
		scr1[1] = 8'h00;
		scr0[1] = 8'h00;
		scr1[2] = 8'h00;
		scr0[2] = 8'h00;
		scr1[3] = 8'h00;
		scr0[3] = 8'h00;
		scr1[4] = 8'h00;
		scr0[4] = 8'h00;
		scr1[5] = 8'h00;
		scr0[5] = 8'h00;
		scr1[6] = 8'h00;
		scr0[6] = 8'h00;
		scr1[7] = 8'h00;
		scr0[7] = 8'h00;
		scr1[8] = 8'h00;
		scr0[8] = 8'h00;
		scr1[9] = 8'h00;
		scr0[9] = 8'h00;
		scr1[10] = 8'h00;
		scr0[10] = 8'h00;
		scr1[11] = 8'h00;
		scr0[11] = 8'h00;
		scr1[12] = 8'h00;
		scr0[12] = 8'h00;
		scr1[13] = 8'h00;
		scr0[13] = 8'h00;
		scr1[14] = 8'h00;
		scr0[14] = 8'h00;
		scr1[15] = 8'h00;
		scr0[15] = 8'h00;
	 end

    // output all the time
    assign rout1 = scr1[sel];
    assign rout0 = scr0[sel];
    
    // write to the registers from the input
    always @(posedge wr1)
    begin
        scr1[sel] <= rin1;
    end
    
    always @(posedge wr0)
    begin
        scr0[sel] <= rin0;
    end
    
endmodule

// alu.v
// D. Hunter 05/28/14
// 08/13/17		DH - fixed carry bug by adding Look Ahead Carry function

// 1802 ALU
// Note: the op codes do not exactly match the 1802 instructions to simplify 
// the interface.  So, translation is needed between the 1802 instructions
// and the ALU op codes.

module alu(op,d,m,cin,out,df);
  input [3:0]op;           // op code
  input [7:0]d;            // accumulator in
  input [7:0]m;        		// memory in
  input cin;					// carry in
  output [7:0]out;			// alu out
  output df;					// carry out
 
  parameter OP_NOP = 4'b0000,
            OP_OR  = 4'b0001,
            OP_AND = 4'b0010,
            OP_XOR = 4'b0011,
            OP_ADD = 4'b0100,
            OP_SD  = 4'b0101,
            OP_SHR = 4'b0110,
            OP_SM  = 4'b0111,
            OP_SHL = 4'b1000,
            OP_SLC = 4'b1001,
            OP_ADC = 4'b1100,
            OP_SDB = 4'b1101,
            OP_SRC = 4'b1110,
            OP_SMB = 4'b1111;

    // generate carry output
  assign df = cout(op,d,m,cin);
    // generate alu output
  assign out = alu_calc(op,d,m,cin);

  // carry output generation
  function cout;
  input [3:0]op;
  input [7:0]a,b;
  input cin;
  begin
    case (op)
        OP_NOP:	cout = cin;
        
        OP_OR:		cout = cin;
            
        OP_AND:	cout = cin;
            
        OP_XOR:	cout = cin;
            
        OP_ADD:	cout = lac4(a[7:4],b[7:4],lac4(a[3:0],b[3:0],1'b0));		// a + b + 0
            
        OP_SD:		cout = lac4(~a[7:4],b[7:4],lac4(~a[3:0],b[3:0],1'b1));	// ~a + b + 1  
      
        OP_SM:		cout = lac4(a[7:4],~b[7:4],lac4(a[3:0],~b[3:0],1'b1));	// a + ~b + 1  
      
        OP_ADC:	cout = lac4(a[7:4],b[7:4],lac4(a[3:0],b[3:0],cin));      // a + b + cin
      
        OP_SDB:	cout = lac4(~a[7:4],b[7:4],lac4(~a[3:0],b[3:0],~cin));	// ~a + b + ~cin
            
        OP_SMB:	cout = lac4(a[7:4],~b[7:4],lac4(a[3:0],~b[3:0],~cin));	// a + ~b + ~cin
            
        OP_SHL:	cout = a[7];
             
        OP_SLC:	cout = a[7];
            
        OP_SHR:	cout = a[0];
            
        OP_SRC:	cout = a[0];
		  
		  default:	cout = cin;
    endcase
  end
  endfunction
  
  // ALU calculation
  function [7:0]alu_calc;
  input [3:0]op;
  input [7:0]a;     // D
  input [7:0]b;     // MEM
  input cin;        // carry in

  begin
      case (op)
        OP_NOP: alu_calc = a;						// no-op
        
        OP_OR:  alu_calc = a | b;				// OR
                
        OP_AND: alu_calc = a & b;				// AND
                
        OP_XOR: alu_calc = a ^ b;				// XOR
                
        OP_ADD: alu_calc = a + b;				// ADD
    
        OP_SD:  alu_calc = b - a;				// SUB (M-D)
    
        OP_SHR: alu_calc = { 1'b0, a[7:1] };	// SHIFT RIGHT

        OP_SM:  alu_calc = a - b;				// SUB (D-M)

        OP_SHL: alu_calc = {a[6:0] , 1'b0 };	// SHIFT LEFT

        OP_SLC: alu_calc = {a[6:0], cin };	// SHIFT LEFT w/ Carry
 
        OP_ADC: alu_calc = a + b + cin;		// ADD w/ Carry
    
        OP_SDB: alu_calc = b + ~a + cin;		// SUB (M-D) w/ Borrow
    
        OP_SRC: alu_calc = { cin, a[7:1] };	// SHIFT RIGHT w/ Carry

        OP_SMB: alu_calc = a + ~b + cin;		// SUB (D-M) w/ Borrow

		  default: alu_calc = a;	// do nothing with an invalid op code
		 
      endcase

    end
    endfunction
  
  
	// 4 bit lock ahead carry
	// Reference: "Digital Circuits and Microprocessors" by Herbert Taub pg 206
	function lac4;
	input [3:0]a;     // A input
	input [3:0]b;     // B input
	input cin;        // carry in
	
	begin
		lac4 = (a[3] & b[3]) + 
				 ((a[3] ^ b[3]) & a[2] & b[2]) + 
				 ((a[3] ^ b[3]) & (a[2] ^ b[2]) & a[1] & b[1]) +
				 ((a[3] ^ b[3]) & (a[2] ^ b[2]) & ((a[1] ^ b[1]) & a[0] & b[0])) +
				 ((a[3] ^ b[3]) & (a[2] ^ b[2]) & (a[1] ^ b[1]) & (a[0] ^ b[0]) & cin);
	end
	endfunction
endmodule
