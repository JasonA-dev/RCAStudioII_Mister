LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

entity dpram is
	generic (
		 addr_width_g : integer := 16;
		 data_width_g : integer := 8
	); 
	PORT
	(
		ram_ad	: IN STD_LOGIC_VECTOR (addr_width_g-1 DOWNTO 0);
		ram_ad_b	: IN STD_LOGIC_VECTOR (addr_width_g-1 DOWNTO 0);
		clk_sys		: IN STD_LOGIC  := '1';
		ram_d		: IN STD_LOGIC_VECTOR (data_width_g-1 DOWNTO 0);
		ram_d_b		: IN STD_LOGIC_VECTOR (data_width_g-1 DOWNTO 0) := (others => '0');
		ram_cs		: IN STD_LOGIC  := '1';
		ram_cs_b		: IN STD_LOGIC  := '1';
		ram_we		: IN STD_LOGIC  := '0';
		ram_we_b		: IN STD_LOGIC  := '0';
		ram_q			: OUT STD_LOGIC_VECTOR (data_width_g-1 DOWNTO 0);
		ram_q_b			: OUT STD_LOGIC_VECTOR (data_width_g-1 DOWNTO 0)
	);
END dpram;

ARCHITECTURE SYN OF dpram IS
BEGIN
	altsyncram_component : altsyncram
	GENERIC MAP (
		address_reg_b => "CLOCK1",
		clock_enable_input_a => "NORMAL",
		clock_enable_input_b => "NORMAL",
		clock_enable_output_a => "BYPASS",
		clock_enable_output_b => "BYPASS",
		indata_reg_b => "CLOCK1",
		intended_device_family => "Cyclone V",
		lpm_type => "altsyncram",
		numwords_a => 2**addr_width_g,
		numwords_b => 2**addr_width_g,
		operation_mode => "BIDIR_DUAL_PORT",
		outdata_aclr_a => "NONE",
		outdata_aclr_b => "NONE",
		outdata_reg_a => "UNREGISTERED",
		outdata_reg_b => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
		widthad_a => addr_width_g,
		widthad_b => addr_width_g,
		width_a => data_width_g,
		width_b => data_width_g,
		width_byteena_a => 1,
		width_byteena_b => 1,
		wrcontrol_wraddress_reg_b => "CLOCK1"
	)
	PORT MAP (
		address_a => ram_ad,
		address_b => ram_ad_b,
		clock0 => clk_sys,
		clock1 => clk_sys,
		clocken0 => ram_cs,
		clocken1 => ram_cs_b,
		data_a => ram_d,
		data_b => ram_d_b,
		wren_a => ram_we,
		wren_b => ram_we_b,
		q_a => ram_q,
		q_b => ram_q_b
	);

END SYN;