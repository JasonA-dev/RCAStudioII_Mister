//
// keyboard.v - Reads key inputs, produces EF lines for the CDP1802
// Original author: JasonA-Dev
// Modified to accept pre-debounced signals from top-level
//
`timescale 1ns / 1ps

module keypad(
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] keys_in,   // These are already debounced
    output wire [3:0] ef_out
);

// In the original Studio II, there's a simple keypad matrix or discrete lines.
// The simplest approach is that each key line might drive a different EF or
// combined logic. For example, let's assume each of the 4 lines sets EF low
// when pressed (CDP1802 sees an active-low EF).
//
// We'll do a direct pass-through in this simple example:
assign ef_out = ~keys_in;  // active low if you want EF = 0 when pressed

endmodule
