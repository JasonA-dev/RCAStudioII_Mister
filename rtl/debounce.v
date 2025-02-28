//
// debounce.v - Simple push-button debouncer
//
// This module synchronizes the input to 'clk' and then waits until the
// input is stable for COUNT_MAX cycles before toggling 'key_out'.
//

`timescale 1ns / 1ps

module debounce #(
    parameter COUNT_MAX = 500000  // Adjust for desired debounce interval
)(
    input  wire clk,
    input  wire rst,
    input  wire key_in,
    output reg  key_out
);

// First, synchronize 'key_in' to the clk domain (2-FF synchronizer).
reg key_sync0, key_sync1;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        key_sync0 <= 1'b0;
        key_sync1 <= 1'b0;
    end else begin
        key_sync0 <= key_in;
        key_sync1 <= key_sync0;
    end
end

// Now implement a counter that waits for stability.
reg [18:0] counter;  // Enough bits to hold COUNT_MAX if it’s up to ~500k
reg stable_state;     // The last stable state of the key

always @(posedge clk or posedge rst) begin
    if (rst) begin
        counter      <= 0;
        stable_state <= 0;
        key_out      <= 0;
    end else begin
        // If the synchronized input matches stable_state, reset the counter
        // because there's no change. If it differs, increment counter.
        // Once counter hits COUNT_MAX, flip stable_state.
        if (key_sync1 == stable_state) begin
            // No change, reset counter
            counter <= 0;
        end else begin
            // Potential change, increment counter
            if (counter < COUNT_MAX) begin
                counter <= counter + 1;
            end else begin
                // Achieved stable transition
                stable_state <= key_sync1;
                counter      <= 0;
            end
        end
        // The output key_out always tracks stable_state
        key_out <= stable_state;
    end
end

endmodule
