// pixie.v
// CDP1861 "PIXIE" emulation
// (c) 2014-2017	David R. Hunter
//
// 07/04/14 DH		- initial version
// 08/27/17	DH		- bug fixes
// 09/03/17 DH 	- reworked unclocked "if" statements to assign
//

// based on data sheets and the ELF 2K PIXIE replacement
// design is based on the 1982 RCA Data book (SSD-260A) pgs.258-265

module pixie(clock_n,reset_n,sc,tpa,tpb,disp_on,disp_off,di,
             clear_n,int_n,efx_n,dmao_n,comp_sync_n,video,vsync_out,hsync_out,VBlank,HBlank,video_de);

    input clock_n;              // dot clock ~ 1.76MHz  
						          				  // NOTE: this is from XTAL_N so it's
										            // inverted from the processor clock
    input reset_n;              // reset input
    input [1:0]sc;              // 1802 state code
    input tpa,tpb;              // 1802 timing pulses
    input disp_on,disp_off;     // display on/off signals
    input [7:0]di;              // data in from 1802

    output clear_n;             // clear output 
    output int_n,efx_n,dmao_n;  // 1802 control signals
    output comp_sync_n,video;   // video output signals
	  output vsync_out;			      // vertical sync (for debugging)
    output hsync_out;			      // vertical sync (for debugging)
	  output VBlank;			        // vertical sync (for debugging)
    output HBlank;			        // vertical sync (for debugging)
    output video_de;			      // vertical sync (for debugging)

    reg video;			// clock the video out through a register
    
    // internal signals
    wire int_out;                // output control signals
    wire efx_out;
    wire dma_out;
    reg  sync_out;               // video output signals
    reg  video_out;
    reg  display_enable;         // display enable from disp_on/disp_off
    wire video_enable;           // signal to blank or enable video
    wire load;                   // signal to load shift register
    wire vsync;                  // vertical sync
    reg  hsync;                  // horizontal sync
    reg  spulse;                 // signal to indicate start of hsync
    reg  rpulse;                 // pulse to reset hsync (delayed 1 tpa)
    reg  rpulse0;                // first pulse during hsync

    // video shift register
    reg [7:0] video_reg;
    
    // counters
    reg [8:0] lc;                // line counter 0-261
    reg [3:0] mc;                // machine cycle counter
    reg [3:0] next_mc;
    reg [3:0] state;             // state machine value
    reg [3:0] next;              // next state
    
    // state code definitions
    parameter FETCH = 2'b00;
    parameter EXEC  = 2'b01;
    parameter DMA   = 2'b10;
    parameter INT   = 2'b11;

    // clear output
    assign clear_n = reset_n;   // just a pass through
    
    // control signals
    assign int_n  = ~int_out;
    assign efx_n  = ~efx_out;
    assign dmao_n = ~dma_out;
    
    // video signals
	 // the original CDP1861 used a serated VSYNC (VSYNC XNOR HSYNC)
    assign comp_sync_n = ~(vsync ^ hsync);  // XNOR operation
    assign video_de  = ~(VBlank | HBlank);

    assign vsync_out = vsync;		// debug output
    assign hsync_out = hsync;		// debug output

    // display enable
    always @(posedge clock_n)
      begin
        if ((!reset_n) || (disp_off))
            display_enable <= 0;
        else if (disp_on)
            display_enable <= 1;
		end
	 
     
    // machine cycle counter
    always @(negedge clock_n)		// clock is inverted from processor
      begin
        if (!reset_n)
            mc <= 4'd13;          // count down from 13
		  else if (tpa)
				mc <= next_mc;
		end
	
	// synchronize machine cycles with the processor
    always @(sc or mc)
      begin
        if (mc == 4'd0)
            if (sc == FETCH)          // if FETCH, skip a clock to keep in 
					    next_mc <= 4'd12;       // sync with the processor
            else 
              next_mc <= 4'd13;       // should always be in EXEC or INT at start of sync
        else
            next_mc <= mc - 4'd1;
      end

    // horizontal sync pulses

    // hsync is asserted on falling edge of tpb (spulse = 1) and 
    // deasserted on the rising edge of the 2nd tpa (rpulse)
    // to give an ~5us pulse width

	 // set pulse is high for mc = 0,13,12
	 always @(negedge tpb or negedge reset_n)
		begin
			if (!reset_n)
				spulse <= 0;
			else if (mc == 4'd12)
				spulse <= 0;
			else if (mc == 4'd0)
				spulse <= 1;
		end
		
	 // delay the spulse to create the rpulse after 2 TPA clocks
	 always @(posedge tpa)
		begin
        rpulse0 <= spulse;
        rpulse  <= rpulse0;
		end

	 // hsync is controlled by set/reset flip-flop
    always @(reset_n or spulse or rpulse)
      begin
        if (!reset_n || rpulse)
            hsync <= 0;             // reset
		  else if (spulse && rpulse)
            hsync <= 0;             // reset if spulse was set and rpulse occurs			
        else if (spulse)
            hsync <= 1;             // start sync on mc 0
      end

    
    // line counter
    always @(posedge hsync or negedge reset_n)
      begin
        if (!reset_n)
            lc <= 9'd0;
        else if (lc == 261)        // at line 262, wrap around
            lc <= 9'd0;
        else
            lc <= lc + 9'd1;
      end

`ifdef SIM		
    always @(negedge hsync)
      begin
        $display(">>> LC = %d",lc);
      end
`endif

	 assign HBlank = (mc < 16 || mc > 80)    ? 1'b1 : 1'b0;  // 64 pixels wide
	 assign VBlank = (lc < 64 || lc >= 261) ? 1'b1 : 1'b0;  // 128 lines for NTSC  

    // vertical sync on lines 0 to 15
	 assign vsync = ((lc >= 9'd0) && (lc < 9'd16)) ? 1'b1 : 1'b0;

    // interrupt output on lines 78 and 79
	 assign int_out = (display_enable && ((lc == 9'd78) || (lc == 9'd79))) ? 1'b1 : 1'b0;
      
    // efx output on lines 76-79 and 204-207
	 assign efx_out = ((display_enable && ((lc == 9'd76) || (lc == 9'd77) || (lc == 9'd78) || (lc == 9'd79))) ||
							(display_enable && ((lc == 9'd204) || (lc == 9'd205) || (lc == 9'd206) || (lc == 9'd207)))) ? 1'b1 : 1'b0;

    // video enable for 128 lines
	 assign video_enable = (display_enable && (lc >= 9'd80) && (lc < 9'd208)) ? 1'b1 : 1'b0;

    // video shift register
    assign load = (tpb && (sc == DMA)); //load with tpb during DMA
    
    always @(posedge clock_n)
      begin
        if (load)
            video_reg <= di;
        else
            video_reg <= {video_reg[6:0], 1'b0};    // shift MSB first
      end

    // clock the video output a half cycle later
	 // to prevent the 8th bit from being shortened 
    always @(negedge clock_n)
      begin
		  if (video_enable)
				video <= video_reg[7];
		  else
				video <= 1'b0;
      end
      
     // handle dma with a state machine
    always @(negedge clock_n)		// clock is inverted from processor
      begin
        if (!reset_n)
            state <= 0;
        else if (tpa)
            state <= next;
      end

    always @(state or hsync or video_enable)
      begin
        case (state)
            0:      if (hsync && video_enable)
                        next <= 1;      // wait for hsync
                    else
                        next <= 0;
            1:      next <= 2;          // wait one machine cycle
            2:      next <= 3;
            3:      next <= 4;
            4:      next <= 5;
            5:      next <= 6;
            6:      next <= 7;
            7:      next <= 8;
            8:      next <= 9;
            9:      next <= 10;
            10:     next <= 11;
            11:     next <= 12;
            12:     next <= 13;
            13:     next <= 0; 
            default:    next <= 0;
        endcase
      end

    // set dma output during cycles 3-11
	 assign dma_out = ((state > 2) && (state < 11)) ? 1'b1 : 1'b0;

endmodule