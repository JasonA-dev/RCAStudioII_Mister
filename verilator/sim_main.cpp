#include <verilated.h>
#include "Vtop.h"

#include "imgui.h"
#include "implot.h"
#ifndef _MSC_VER
#include <stdio.h>
#include <SDL.h>
#include <SDL_opengl.h>
#else
#define WIN32
#include <dinput.h>
#endif

#include "sim_console.h"
#include "sim_bus.h"
#include "sim_video.h"
#include "sim_audio.h"
#include "sim_input.h"
#include "sim_clock.h"

#include "../imgui/imgui_memory_editor.h"
#include <verilated_vcd_c.h> //VCD Trace
#include "../imgui/ImGuiFileDialog.h"

#include <iostream>
#include <fstream>
using namespace std;

// Simulation control
// ------------------
int initialReset = 48;
bool run_enable = 0;
int batchSize = 150000;
bool single_step = 0;
bool multi_step = 0;
int multi_step_amount = 1024;

// Debug GUI 
// ---------
const char* windowTitle = "Verilator Sim: RCA Studio II";
const char* windowTitle_Control = "Simulation control";
const char* windowTitle_DebugLog = "Debug log";
const char* windowTitle_Video = "VGA output";
const char* windowTitle_Trace = "Trace/VCD control";
const char* windowTitle_Audio = "Audio output";
bool showDebugLog = true;
DebugConsole console;
MemoryEditor mem_edit;

// HPS emulator
// ------------
SimBus bus(console);

// Input handling
// --------------
SimInput input(12, console);
const int input_right = 0;
const int input_left = 1;
const int input_down = 2;
const int input_up = 3;
const int input_fire1 = 4;
const int input_fire2 = 5;
const int input_start_1 = 6;
const int input_start_2 = 7;
const int input_coin_1 = 8;
const int input_coin_2 = 9;
const int input_coin_3 = 10;
const int input_pause = 11;

// Video
// -----
#define VGA_WIDTH 128
#define VGA_HEIGHT 128
#define VGA_ROTATE 0  // 90 degrees anti-clockwise
#define VGA_SCALE_X vga_scale
#define VGA_SCALE_Y vga_scale
SimVideo video(VGA_WIDTH, VGA_HEIGHT, VGA_ROTATE);
float vga_scale = 5;

// Verilog module
// --------------
Vtop* top = NULL;

vluint64_t main_time = 0;	// Current simulation time.
double sc_time_stamp() {	// Called by $time in Verilog.
	return main_time;
}

int clk_sys_freq = 48000000;
SimClock clk_48(1); 
SimClock clk_24(2); 

// VCD trace logging
// -----------------
VerilatedVcdC* tfp = new VerilatedVcdC; //Trace
bool Trace = 0;
char Trace_Deep[3] = "99";
char Trace_File[30] = "sim.vcd";
char Trace_Deep_tmp[3] = "99";
char Trace_File_tmp[30] = "sim.vcd";
int  iTrace_Deep_tmp = 99;
char SaveModel_File_tmp[20] = "test", SaveModel_File[20] = "test";

//Trace Save/Restore
void save_model(const char* filenamep) {
	VerilatedSave os;
	os.open(filenamep);
	os << main_time; // user code must save the timestamp, etc
	os << *top;
}
void restore_model(const char* filenamep) {
	VerilatedRestore os;
	os.open(filenamep);
	os >> main_time;
	os >> *top;
}

// Audio
// -----
#define DISABLE_AUDIO
#ifndef DISABLE_AUDIO
SimAudio audio(clk_sys_freq, true);
#endif

// Reset simulation variables and clocks
void resetSim() {
	main_time = 0;
	clk_48.Reset();
	clk_24.Reset();
}

int verilate() {

	if (!Verilated::gotFinish()) {

		// Assert reset during startup
		//if (main_time < initialReset) { top->reset = 1; }
		// Deassert reset after startup
		//if (main_time == initialReset) { top->reset = 0; }

		// Clock dividers
		clk_48.Tick();
		clk_24.Tick();

		// Set clocks in core
		top->clk_48 = clk_48.clk;
		top->clk_24 = clk_24.clk;

		// Simulate both edges of fastest clock
		if (clk_48.clk != clk_48.old) {

			// System clock simulates HPS functions
			if (clk_48.clk) {
				input.BeforeEval();
				bus.BeforeEval();
			}
			top->eval();
			if (Trace) {
				if (!tfp->isOpen()) tfp->open(Trace_File);
				tfp->dump(main_time); //Trace
			}

			// System clock simulates HPS functions
			if (clk_48.clk) { bus.AfterEval(); }
		}

#ifndef DISABLE_AUDIO
		if (clk_48.IsRising())
		{
			audio.Clock(top->AUDIO_L, top->AUDIO_R);
		}
#endif

		// Output pixels on rising edge of pixel clock
		if (clk_48.IsRising() && top->top__DOT__ce_pix) {
			uint32_t colour = 0xFF000000 | top->VGA_B << 16 | top->VGA_G << 8 | top->VGA_R;
			video.Clock(top->VGA_HB, top->VGA_VB, top->VGA_HS, top->VGA_VS, colour);
		}

		if (clk_48.IsRising()) {
			main_time++;
		}
		return 1;
	}

	// Stop verilating and cleanup
	top->final();
	delete top;
	exit(0);
	return 0;
}

int main(int argc, char** argv, char** env) {

	// Create core and initialise
	top = new Vtop();
	Verilated::commandArgs(argc, argv);

	//Prepare for Dump Signals
	Verilated::traceEverOn(true); //Trace
	top->trace(tfp, 1);// atoi(Trace_Deep) );  // Trace 99 levels of hierarchy
	if (Trace) tfp->open(Trace_File);//"simx.vcd"); //Trace

#ifdef WIN32
	// Attach debug console to the verilated code
	Verilated::setDebug(console);
#endif

	// Attach bus
	bus.ioctl_addr = &top->ioctl_addr;
	bus.ioctl_index = &top->ioctl_index;
	bus.ioctl_wait = &top->ioctl_wait;
	bus.ioctl_download = &top->ioctl_download;
	bus.ioctl_upload = &top->ioctl_upload;
	bus.ioctl_wr = &top->ioctl_wr;
	bus.ioctl_dout = &top->ioctl_dout;
	bus.ioctl_din = &top->ioctl_din;
    input.ps2_key = &top->ps2_key;

#ifndef DISABLE_AUDIO
	audio.Initialise();
#endif

	// Set up input module
	input.Initialise();
#ifdef WIN32
	input.SetMapping(input_up, DIK_UP);
	input.SetMapping(input_right, DIK_RIGHT);
	input.SetMapping(input_down, DIK_DOWN);
	input.SetMapping(input_left, DIK_LEFT);
	input.SetMapping(input_fire1, DIK_SPACE);
	input.SetMapping(input_start_1, DIK_1);
	input.SetMapping(input_start_2, DIK_2);
	input.SetMapping(input_coin_1, DIK_5);
	input.SetMapping(input_coin_2, DIK_6);
	input.SetMapping(input_coin_3, DIK_7);
	input.SetMapping(input_pause, DIK_P);
#else
	input.SetMapping(input_up, SDL_SCANCODE_UP);
	input.SetMapping(input_right, SDL_SCANCODE_RIGHT);
	input.SetMapping(input_down, SDL_SCANCODE_DOWN);
	input.SetMapping(input_left, SDL_SCANCODE_LEFT);
	input.SetMapping(input_fire1, SDL_SCANCODE_SPACE);
	input.SetMapping(input_start_1, SDL_SCANCODE_1);
	input.SetMapping(input_start_2, SDL_SCANCODE_2);
	input.SetMapping(input_coin_1, SDL_SCANCODE_3);
	input.SetMapping(input_coin_2, SDL_SCANCODE_4);
	input.SetMapping(input_coin_3, SDL_SCANCODE_5);
	input.SetMapping(input_pause, SDL_SCANCODE_P);
#endif
	// Setup video output
	if (video.Initialise(windowTitle) == 1) { return 1; }

	bus.QueueDownload("./boot.rom", 0, true);


#ifdef WIN32
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT)
	{
		if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			continue;
		}
#else
	bool done = false;
	while (!done)
	{
		SDL_Event event;
		while (SDL_PollEvent(&event))
		{
			ImGui_ImplSDL2_ProcessEvent(&event);
			if (event.type == SDL_QUIT)
				done = true;
		}
#endif
		video.StartFrame();

		input.Read();


		// Draw GUI
		// --------
		ImGui::NewFrame();

		// Simulation control window
		ImGui::Begin(windowTitle_Control);
		ImGui::SetWindowPos(windowTitle_Control, ImVec2(0, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Control, ImVec2(500, 150), ImGuiCond_Once);
		if (ImGui::Button("Reset simulation")) { resetSim(); } ImGui::SameLine();
		if (ImGui::Button("Start running")) { run_enable = 1; } ImGui::SameLine();
		if (ImGui::Button("Stop running")) { run_enable = 0; } ImGui::SameLine();
		ImGui::Checkbox("RUN", &run_enable);
		//ImGui::PopItemWidth();
		ImGui::SliderInt("Run batch size", &batchSize, 1, 250000);
		if (single_step == 1) { single_step = 0; }
		if (ImGui::Button("Single Step")) { run_enable = 0; single_step = 1; }
		ImGui::SameLine();
		if (multi_step == 1) { multi_step = 0; }
		if (ImGui::Button("Multi Step")) { run_enable = 0; multi_step = 1; }
		//ImGui::SameLine();
		ImGui::SliderInt("Multi step amount", &multi_step_amount, 8, 1024);
		if (ImGui::Button("Load ST2"))
    	ImGuiFileDialog::Instance()->OpenDialog("ChooseFileDlgKey", "Choose File", ".st2", ".");
		ImGui::SameLine();
		if (ImGui::Button("Load BIN"))
    	ImGuiFileDialog::Instance()->OpenDialog("ChooseFileDlgKey", "Choose File", ".bin", ".");
		ImGui::End();

		// Debug log window
		console.Draw(windowTitle_DebugLog, &showDebugLog, ImVec2(500, 700));
		ImGui::SetWindowPos(windowTitle_DebugLog, ImVec2(0, 160), ImGuiCond_Once);

		// Memory debug
		//ImGui::Begin("ROM");
		//mem_edit.DrawContents(&top->top__DOT__rcastudio__DOT__Rom_StudioII__DOT__d, 2048, 0);
		//ImGui::End();
		ImGui::Begin("DPRAM");
		mem_edit.DrawContents(&top->top__DOT__rcastudio__DOT__dpram__DOT__mem, 4096, 0);
		ImGui::End();		
		//ImGui::Begin("Pixie Studio II Row Cache");
		//mem_edit.DrawContents(&top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__row_cache, 8, 0);		
		//ImGui::End();
		//ImGui::Begin("Pixie Studio II Frame Buffer");
		//mem_edit.DrawContents(&top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__frame_buffer, 256, 0);		
		//ImGui::End();

/*
		// Debug 1802 cpu
		ImGui::Begin("CDP 1802 Registers");
		ImGui::Text("P:       0x%04X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__P);	
		ImGui::Text("X:       0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__X);
		ImGui::Text("R:       0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__R);	
		ImGui::Text("Ra:      0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__Ra);			
		ImGui::Text("Rrd:     0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__Rrd);	
		ImGui::Text("Rwd:     0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__Rwd);	
		ImGui::Text("D:       0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__D);
		ImGui::Text("DF:      0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__DF);	
		ImGui::Text("B:       0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__B);	
		ImGui::Text("I:       0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__I);	
		ImGui::Text("N:       0x%02X", top->top__DOT__rcastudio__DOT__cdp1802__DOT__N);	
		ImGui::Spacing();		
		ImGui::End();
*/

		ImGui::Begin("CDP 1802 NEW");
		ImGui::Text("clr_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__clr_n);	
		ImGui::Text("wait_n:     0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__wait_n);	
		ImGui::Text("dmai_n:     0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__dmai_n);
		ImGui::Text("dmao_n:     0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__dmao_n);	
		ImGui::Text("int_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__int_n);
		ImGui::Text("ef1_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__ef1_n);	
		ImGui::Text("ef2_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__ef2_n);	
		ImGui::Text("ef3_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__ef3_n);					
		ImGui::Text("ef4_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__ef4_n);	
		ImGui::Spacing();	
		ImGui::Text("data_in:    0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__data_in);
		ImGui::Text("xtal_n:     0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__xtal_n);	
		ImGui::Text("tpa:        0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__tpa);	
		ImGui::Text("tpb:        0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__tpb);			
		ImGui::Text("mwr_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__mwr_n);	
		ImGui::Text("mrd_n:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__mrd_n);	
		ImGui::Spacing();	
		ImGui::Text("sc:         0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__sc);
		ImGui::Text("q:          0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__q);	
		ImGui::Text("n_out:      0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__n_out);	
		ImGui::Text("data_out:   0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__data_out);			
		ImGui::Text("ma:         0x%04X", top->top__DOT__rcastudio__DOT__U1__DOT__ma);	
		ImGui::Text("ma1:        0x%04X", top->top__DOT__rcastudio__DOT__U1__DOT__ma1);	
		ImGui::Text("oe_n:       0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__oe_n);			
		ImGui::Text("cycle_out:  0x%02X", top->top__DOT__rcastudio__DOT__U1__DOT__cycle_out);				
		ImGui::Spacing();		
		ImGui::End();

		// Debug Pixie Video
		ImGui::Begin("Pixie Video");
		ImGui::Text("reset_n:       0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__reset_n);		
		ImGui::Text("sc:            0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__sc);	
		ImGui::Text("tpa:           0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__tpa);
		ImGui::Text("tpb:           0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__tpb);					
		ImGui::Text("disp_on:       0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__disp_on);	
		ImGui::Text("disp_off:      0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__disp_off);
		ImGui::Spacing();			
		ImGui::Text("di:            0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__di);
		ImGui::Spacing();	
		ImGui::Text("int_n:         0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__int_n);
		ImGui::Text("dmao_n:        0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__dmao_n);
		ImGui::Text("efx_n:         0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__efx_n);
		ImGui::Spacing();
		ImGui::Text("comp_sync_n:   0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__comp_sync_n);
		ImGui::Text("video:         0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__video);
		ImGui::Spacing();
		ImGui::Text("vsync_out:     0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__hsync_out);
		ImGui::Text("hsync_out:     0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__hsync_out);
		ImGui::Text("VBlank:        0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__VBlank);
		ImGui::Text("HBlank:        0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__HBlank);
		ImGui::Text("video_de:      0x%02X", top->top__DOT__rcastudio__DOT__PIXIE__DOT__video_de);								
		ImGui::End();
/*
		ImGui::Begin("Pixie Video Studio II");
		ImGui::Text("enabled:       0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__display_enabled);			
		ImGui::Text("disp_on:       0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__disp_on);	
		ImGui::Text("disp_off:      0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__disp_off);
		ImGui::Text("SC:            0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__SC);		
		ImGui::Text("data_in:       0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__data_in);
		ImGui::Text("DMAO:          0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__DMAO);	
		ImGui::Text("DMA_xfer:      0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__DMA_xfer);			
		ImGui::Text("INT:           0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__INT);	
		ImGui::Text("EFx:           0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__EFx);							
		ImGui::Spacing();	
		ImGui::Text("mem_addr:      0x%04X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__mem_addr);
		ImGui::Spacing();	
		ImGui::Text("hori_pixel_counter: 0x%04X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__horizontal_pixel_counter);
		ImGui::Text("ver_pixel_counter:  0x%04X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__vertical_pixel_counter);
		ImGui::Text("pixel_shift_reg:    0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__pixel_shift_reg);		
		ImGui::Spacing();	
		ImGui::Text("HSync:          0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__HSync);
		ImGui::Text("VSync:          0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__VSync);
		ImGui::Text("VBlank:         0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__VBlank);
		ImGui::Text("HBlank:         0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__HBlank);		
		ImGui::Text("video_de:       0x%02X", top->top__DOT__rcastudio__DOT__pixie_video__DOT__pixie_video_studioii__DOT__video_de);								
		ImGui::End();
*/
		// Debug ioctl
		ImGui::Begin("ioctl");
		ImGui::Text("ioctl_download: 0x%02X", top->top__DOT__rcastudio__DOT__ioctl_download);	
		ImGui::Text("ioctl_wr:       0x%02X", top->top__DOT__rcastudio__DOT__ioctl_wr);
		ImGui::Text("ioctl_addr:     0x%04X", top->top__DOT__rcastudio__DOT__ioctl_addr);
		ImGui::Text("ioctl_dout:     0x%02X", top->top__DOT__rcastudio__DOT__ioctl_dout);		
		ImGui::Spacing();														
		ImGui::End();

		// Debug sim
		ImGui::Begin("Sim");
		ImGui::Text("reset:	  0x%02X", top->top__DOT__rcastudio__DOT__reset);	
		ImGui::Text("ps2_key:	0x%02X", top->top__DOT__ps2_key);		
		ImGui::Text("code:	   0x%02X", top->top__DOT__rcastudio__DOT__code);	
		ImGui::Text("pressed:	0x%02X", top->top__DOT__rcastudio__DOT__pressed);			
		ImGui::Spacing();														
		ImGui::End();

		// Debug Keypad 1
//		ImGui::Begin("Keypad 1");
//		ImGui::Text("btnKP1: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1);	
		/*ImGui::Text("btnKP1_2: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_2);
		ImGui::Text("btnKP1_3: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_3);
		ImGui::Text("btnKP1_4: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_4);
		ImGui::Text("btnKP1_5: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_5);		
		ImGui::Text("btnKP1_6: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_6);	
		ImGui::Text("btnKP1_7: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_7);
		ImGui::Text("btnKP1_8: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_8);
		ImGui::Text("btnKP1_9: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_9);
		ImGui::Text("btnKP1_0: 	0x%02X", top->top__DOT__rcastudio__DOT__btnKP1_0);	*/						
//		ImGui::Spacing();														
//		ImGui::End();

		//PlayerA
		ImGui::Begin("Controls");
		ImGui::Text("Player A: 	0x%03X", top->top__DOT__rcastudio__DOT__playerA);
		ImGui::Text("Player B: 	0x%03X", top->top__DOT__rcastudio__DOT__playerB);
		ImGui::Text("KeyLatch: 	0x%03X", top->top__DOT__rcastudio__DOT__keylatch);
		ImGui::Spacing();														
		ImGui::End();
		
		// Trace/VCD window
		ImGui::Begin(windowTitle_Trace);
		ImGui::SetWindowPos(windowTitle_Trace, ImVec2(0, 870), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Trace, ImVec2(500, 150), ImGuiCond_Once);

		if (ImGui::Button("Start VCD Export")) { Trace = 1; } ImGui::SameLine();
		if (ImGui::Button("Stop VCD Export")) { Trace = 0; } ImGui::SameLine();
		if (ImGui::Button("Flush VCD Export")) { tfp->flush(); } ImGui::SameLine();
		ImGui::Checkbox("Export VCD", &Trace);

		ImGui::PushItemWidth(120);
		if (ImGui::InputInt("Deep Level", &iTrace_Deep_tmp, 1, 100, ImGuiInputTextFlags_EnterReturnsTrue))
		{
			top->trace(tfp, iTrace_Deep_tmp);
		}

		if (ImGui::InputText("TraceFilename", Trace_File_tmp, IM_ARRAYSIZE(Trace_File), ImGuiInputTextFlags_EnterReturnsTrue))
		{
			strcpy(Trace_File, Trace_File_tmp); //TODO onChange Close and open new trace file
			tfp->close();
			if (Trace) tfp->open(Trace_File);
		};
		ImGui::Separator();
		if (ImGui::Button("Save Model")) { save_model(SaveModel_File); } ImGui::SameLine();
		if (ImGui::Button("Load Model")) {
			restore_model(SaveModel_File);
		} ImGui::SameLine();
		if (ImGui::InputText("SaveFilename", SaveModel_File_tmp, IM_ARRAYSIZE(SaveModel_File), ImGuiInputTextFlags_EnterReturnsTrue))
		{
			strcpy(SaveModel_File, SaveModel_File_tmp); //TODO onChange Close and open new trace file
		}
		ImGui::End();
		int windowX = 550;
		int windowWidth = (VGA_WIDTH * VGA_SCALE_X) + 24;
		int windowHeight = (VGA_HEIGHT * VGA_SCALE_Y) + 90;

		// Video window
		ImGui::Begin(windowTitle_Video);
		ImGui::SetWindowPos(windowTitle_Video, ImVec2(windowX, 0), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Video, ImVec2(windowWidth, windowHeight), ImGuiCond_Once);

		ImGui::SetNextItemWidth(400);
		ImGui::SliderFloat("Zoom", &vga_scale, 1, 8); ImGui::SameLine();
		ImGui::SetNextItemWidth(200);
		ImGui::SliderInt("Rotate", &video.output_rotate, -1, 1); ImGui::SameLine();
		ImGui::Checkbox("Flip V", &video.output_vflip);
		ImGui::Text("main_time: %d frame_count: %d sim FPS: %f", main_time, video.count_frame, video.stats_fps);
		//ImGui::Text("pixel: %06d line: %03d", video.count_pixel, video.count_line);

		// Draw VGA output
		ImGui::Image(video.texture_id, ImVec2(video.output_width * VGA_SCALE_X, video.output_height * VGA_SCALE_Y));
		ImGui::End();

  		if (ImGuiFileDialog::Instance()->Display("ChooseFileDlgKey"))
  		{
    		// action if OK
    		if (ImGuiFileDialog::Instance()->IsOk())
    		{
      			std::string filePathName = ImGuiFileDialog::Instance()->GetFilePathName();
      			std::string filePath = ImGuiFileDialog::Instance()->GetCurrentPath();
      			// action
				fprintf(stderr,"filePathName: %s\n",filePathName.c_str());
				fprintf(stderr,"filePath: %s\n",filePath.c_str());
     			bus.QueueDownload(filePathName, 1, 1);
    		}
    		// close
    		ImGuiFileDialog::Instance()->Close();
  		}

#ifndef DISABLE_AUDIO

		ImGui::Begin(windowTitle_Audio);
		ImGui::SetWindowPos(windowTitle_Audio, ImVec2(windowX, windowHeight), ImGuiCond_Once);
		ImGui::SetWindowSize(windowTitle_Audio, ImVec2(windowWidth, 250), ImGuiCond_Once);


		//float vol_l = ((signed short)(top->AUDIO_L) / 256.0f) / 256.0f;
		//float vol_r = ((signed short)(top->AUDIO_R) / 256.0f) / 256.0f;
		//ImGui::ProgressBar(vol_l + 0.5f, ImVec2(200, 16), 0); ImGui::SameLine();
		//ImGui::ProgressBar(vol_r + 0.5f, ImVec2(200, 16), 0);

		int ticksPerSec = (24000000 / 60);
		if (run_enable) {
			audio.CollectDebug((signed short)top->AUDIO_L, (signed short)top->AUDIO_R);
		}
		int channelWidth = (windowWidth / 2) - 16;
		ImPlot::CreateContext();
		if (ImPlot::BeginPlot("Audio - L", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_l, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImGui::SameLine();
		if (ImPlot::BeginPlot("Audio - R", ImVec2(channelWidth, 220), ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
			ImPlot::SetupAxes("T", "A", ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks, ImPlotAxisFlags_AutoFit | ImPlotAxisFlags_NoLabel | ImPlotAxisFlags_NoTickMarks);
			ImPlot::SetupAxesLimits(0, 1, -1, 1, ImPlotCond_Once);
			ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_r, audio.debug_max_samples, audio.debug_pos);
			ImPlot::EndPlot();
		}
		ImPlot::DestroyContext();
		ImGui::End();
#endif

		video.UpdateTexture();


		// Pass inputs to sim
		top->inputs = 0;
		for (int i = 0; i < input.inputCount; i++)
		{
			if (input.inputs[i]) { top->inputs |= (1 << i); }
		}

		// Run simulation
		if (run_enable) {
			for (int step = 0; step < batchSize; step++) { verilate(); }
		}
		else {
			if (single_step) { verilate(); }
			if (multi_step) {
				for (int step = 0; step < multi_step_amount; step++) { verilate(); }
			}
		}
	}

	// Clean up before exit
	// --------------------

#ifndef DISABLE_AUDIO
	audio.CleanUp();
#endif 
	video.CleanUp();
	input.CleanUp();

	return 0;
}
