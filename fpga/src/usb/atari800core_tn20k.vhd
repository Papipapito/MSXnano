---------------------------------------------------------------------------
-- Port to ZX-UNO by Quest 2016
--
-- Ahora tambien para UnAmiga, Jepalza 2018
-- empleando partes del Reverse U16
--
-- (c) 2013-2015 mark watson
-- I am happy for anyone to use this for non-commercial use.
-- If my vhdl files are used commercially or otherwise sold,
-- please contact me for explicit permission at scrameta (gmail).
-- This applies for source and binary form and derived works.
---------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all; 
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

LIBRARY work;

ENTITY atari800core_tn20k IS 
	GENERIC
	(
		internal_rom : integer := 0 ;
		internal_ram : integer := 0
	);
	PORT
	(
		CLK_IN :  IN  STD_LOGIC; 

		-- RGB LED
		WS_2812 : OUT STD_LOGIC;

  -- interface to Tang onboard BL616 UART
  		uart_rx :  IN  STD_LOGIC; 
  		uart_tx :  OUT  STD_LOGIC; 
  -- onboard Bl616 monitor console port interface
		bl616_mon_tx :  OUT  STD_LOGIC;
		bl616_mon_rx :  IN  STD_LOGIC;

		-- interface to external FPGA companion - USB KEYBOARD and gamepads
		m0s : INOUT STD_LOGIC_VECTOR(4 DOWNTO 0);


  --SPI connection to ob-board BL616. By default an external
  --connection is used with a M0S Dock
		spi_sclk :  IN  STD_LOGIC; 
		spi_csn :  IN  STD_LOGIC; 
		spi_dir :  OUT  STD_LOGIC;
		spi_dat :  IN  STD_LOGIC; 
		spi_irqn :  OUT  STD_LOGIC;

		-- onboard audio i2s
		-- pa_en : OUT STD_LOGIC;
		-- hp_din : OUT STD_LOGIC;
		-- hp_ws : OUT STD_LOGIC;
		-- hp_bck : OUT STD_LOGIC;

		
		-- led
		LEDS			: OUT  std_logic_vector(2 downto 0);
		-- botones
		KEY			: IN  std_logic_vector(1 downto 0);
		
		SD_MISO 		 : IN  STD_LOGIC;
		SD_SCK 		 : OUT  STD_LOGIC;
		SD_MOSI 		 : OUT  STD_LOGIC;
		SD_nCS 		 : OUT  STD_LOGIC;

		-- HDMI / TMDS
		tmds_clk_n : OUT STD_LOGIC;
		tmds_clk_p : OUT STD_LOGIC;
		tmds_d_n : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
		tmds_d_p : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);

		-- TANG NANO 20K
    	-- "Magic" port names that the gowin compiler connects to the on-chip SDRAM
        O_sdram_clk : OUT STD_LOGIC;
        O_sdram_cke : OUT STD_LOGIC;
        O_sdram_cs_n : OUT STD_LOGIC;
        O_sdram_cas_n : OUT STD_LOGIC;
        O_sdram_ras_n : OUT STD_LOGIC;
        O_sdram_wen_n : OUT STD_LOGIC;
        IO_sdram_dq : INOUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        O_sdram_addr : OUT STD_LOGIC_VECTOR(10 DOWNTO 0);
        O_sdram_ba : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        O_sdram_dqm : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)

	);
END atari800core_tn20k;

ARCHITECTURE vhdl OF atari800core_tn20k IS 

component CLKDIV
	generic (
		DIV_MODE : STRING := "2";
		GSREN: in string := "false"
	);
	port (
		CLKOUT: out std_logic;
		HCLKIN: in std_logic;
		RESETN: in std_logic;
		CALIB: in std_logic
	);
end component;

component hq_dac
port (
  reset :in std_logic;
  clk :in std_logic;
  clk_ena : in std_logic;
  pcm_in : in std_logic_vector(19 downto 0);
  dac_out : out std_logic
);
end component;

	signal keyboard : std_logic_vector(127 downto 0);
	signal joystick0 : std_logic_vector(7 downto 0);
	signal joystick0_console : std_logic_vector(7 downto 0);
	signal joystick1 : std_logic_vector(7 downto 0);
	signal ws2812_color : std_logic_vector(23 downto 0);
	signal pixel_enable : std_logic;

	signal AUDIO_L_PCM : std_logic_vector(15 downto 0);
	signal AUDIO_R_PCM : std_logic_vector(15 downto 0);
	
	signal VIDEO_VS : std_logic;
	signal VIDEO_HS : std_logic;
	signal VIDEO_CS : std_logic;
	signal VIDEO_R : std_logic_vector(7 downto 0);
	signal VIDEO_G : std_logic_vector(7 downto 0);
	signal VIDEO_B : std_logic_vector(7 downto 0);
	--
	--signal VIDEO_BLANK		: std_logic;
	signal VIDEO_COLOR		: std_logic_vector(7 downto 0);
	signal VIDEO_VS_RAW		: std_logic;
	signal VIDEO_HS_RAW		: std_logic;
	signal VIDEO_BLANK_RAW		: std_logic;
	signal PAL			: std_logic := '0';
	--
	signal VIDEO_BLANK : std_logic;
	signal VIDEO_BURST : std_logic;
	signal VIDEO_START_OF_FIELD : std_logic;
	signal VIDEO_ODD_LINE : std_logic;


	--signal PAL : std_logic;
	
	signal JOY1_IN_N : std_logic_vector(4 downto 0);
	signal JOY2_IN_N : std_logic_vector(4 downto 0);

	signal PLL1_LOCKED : std_logic;
	signal CLK_PLL1 : std_logic;

	signal CLK_28 : std_logic;

	
	signal RESET_N : std_logic;
	signal PLL_LOCKED : std_logic;
	signal CLK : std_logic;
	signal CLK_SDRAM : std_logic;
	signal HDMI_PLL_LOCKED : std_logic;
	signal CLK_142 : std_logic;

	-- pokey keyboard
	SIGNAL KEYBOARD_SCAN : std_logic_vector(5 downto 0);
	SIGNAL KEYBOARD_RESPONSE : std_logic_vector(1 downto 0);
	signal atari_keyboard : std_logic_vector(63 downto 0);
	
	-- gtia consol keys
	SIGNAL CONSOL_START : std_logic;
	SIGNAL CONSOL_SELECT : std_logic;
	SIGNAL CONSOL_OPTION : std_logic;
	SIGNAL FKEYS : std_logic_vector(11 downto 0);

	-- scandoubler
	signal half_scandouble_enable_reg : std_logic;
	signal half_scandouble_enable_next : std_logic;
	signal scanlines_reg : std_logic := '0';
	signal scanlines_next : std_logic := '0';
 	SIGNAL COMPOSITE_ON_HSYNC : std_logic := '1';
 	SIGNAL VGA : std_logic := '1';

	-- dma/virtual drive
	signal DMA_ADDR_FETCH : std_logic_vector(23 downto 0);
	signal DMA_WRITE_DATA : std_logic_vector(31 downto 0);
	signal DMA_FETCH : std_logic;
	signal DMA_32BIT_WRITE_ENABLE : std_logic;
	signal DMA_16BIT_WRITE_ENABLE : std_logic;
	signal DMA_8BIT_WRITE_ENABLE : std_logic;
	signal DMA_READ_ENABLE : std_logic;
	signal DMA_MEMORY_READY : std_logic;
	signal DMA_MEMORY_DATA : std_logic_vector(31 downto 0);

	signal ZPU_ADDR_ROM : std_logic_vector(15 downto 0);
	signal ZPU_ROM_DATA :  std_logic_vector(31 downto 0);

	signal ZPU_OUT1 : std_logic_vector(31 downto 0);
	signal ZPU_OUT2 : std_logic_vector(31 downto 0);
	signal ZPU_OUT3 : std_logic_vector(31 downto 0);
	signal ZPU_OUT4 : std_logic_vector(31 downto 0);
	signal ZPU_OUT5 : std_logic_vector(31 downto 0);
	signal ZPU_OUT6 : std_logic_vector(31 downto 0);

	signal zpu_pokey_enable : std_logic;
	signal zpu_sio_txd : std_logic;
	signal zpu_sio_rxd : std_logic;
	signal zpu_sio_command : std_logic;
	SIGNAL ASIO_CLOCKOUT : std_logic;

	-- system control from zpu
	signal ram_select : std_logic_vector(2 downto 0);
	signal reset_atari : std_logic;
	signal pause_atari : std_logic;
	SIGNAL speed_6502 : std_logic_vector(5 downto 0);
	signal turbo_vblank_only : std_logic;
	signal emulated_cartridge_select: std_logic_vector(5 downto 0);
	signal atari800mode : std_logic;

	-- turbo freezer!
	signal freezer_enable : std_logic;
	signal freezer_activate: std_logic;

	signal PS2_KEYS : STD_LOGIC_VECTOR(511 downto 0) := (others=>'0');
	signal PS2_KEYS_NEXT : STD_LOGIC_VECTOR(511 downto 0) := (others=>'0');
	signal USB_KEYS : STD_LOGIC_VECTOR(127 downto 0);
	signal USB_KEYS_NEXT : STD_LOGIC_VECTOR(127 downto 0);

	-- RAM interna
	signal ram_addr : std_logic_vector(22 downto 0);
	signal ram_do : std_logic_vector(31 downto 0);
	signal ram_di : std_logic_vector(31 downto 0);

	-- SDRAM hacia RAM
	signal ram_request		: std_logic;
	signal ram_request_complete	: std_logic;
	signal ram_write_enable	: std_logic;
	signal ram_read_enable	: std_logic;
	signal ram_refresh		: std_logic;
	--
	signal SDRAM_WIDTH_8BIT_ACCESS 	: std_logic;
	signal SDRAM_WIDTH_16BIT_ACCESS	: std_logic;
	signal SDRAM_WIDTH_32BIT_ACCESS	: std_logic;
	signal SDRAM_RESET_N 		: std_logic;
	--
	signal CLK_SDRAM_IN			:std_logic; -- jepalza, reloj 114.28 para el modulo SDRAM
	--
	signal CLK_HDMI_IN			:std_logic;
	signal CLK_PIXEL_IN			:std_logic;
	--
	signal VIDEOSW : std_logic := '0';
	signal SCANL : std_logic := '0';
	signal VIDEOSTD : std_logic :='0';
	signal tv : std_logic :='0';
	signal REBOOT : std_logic := '0';
--	signal CLK_MULTIBOOT : std_logic;
	signal scandoubler_ctrl: std_logic;
	
-- volver a definir la vga
	signal		VGA_VS_DELAYED 	:   STD_LOGIC;
	signal		VGA_HS_DELAYED 	:   STD_LOGIC;	
	signal		VGA_VS 	:   STD_LOGIC;
	signal		VGA_HS 	:   STD_LOGIC;
	signal		VGA_B 	:   STD_LOGIC_VECTOR(5 DOWNTO 0);
	signal		VGA_G 	:   STD_LOGIC_VECTOR(5 DOWNTO 0);
	signal		VGA_R 	:   STD_LOGIC_VECTOR(5 DOWNTO 0);	
	
	

---- jepalza, ajustes vga LX16
--	signal VGA_R4 : STD_LOGIC_VECTOR(3 downto 0);
--	signal VGA_G4 : STD_LOGIC_VECTOR(3 downto 0);
--	signal VGA_B4 : STD_LOGIC_VECTOR(3 downto 0);

	
BEGIN 


	main_pll: entity work.pll_114m 
	port map (
		clkin 	=> CLK_IN,
		clkoutd	=> CLK,		-- 56.64 (1.77 * 32) --TN20K - 57
		clkout	=> CLK_SDRAM_IN,	-- 113.28 --TN20K - 114
		clkoutp	=> O_sdram_clk,		-- 113.28 (shifted) -2.42nz (unos 90 grados)
		--c3	=> CLK_HDMI_IN,		-- 141.6 (pixel clock * 5)
		--c4	=> CLK_PIXEL_IN,	-- 28.32
		lock	=> PLL_LOCKED
	);

	hdmi_pll: entity work.pll_HDMI 
	port map (
		clkin 	=> CLK, -- 57 MHz
		clkout	=> CLK_142,	-- 113.28 --TN20K - 114
		--c3	=> CLK_HDMI_IN,		-- 141.6 (pixel clock * 5)
		--c4	=> CLK_PIXEL_IN,	-- 28.32
		lock	=> HDMI_PLL_LOCKED
	);

CLKDIV_I1:  CLKDIV 
generic map (
    DIV_MODE => "2",
    GSREN => "false"
) port map (
    CLKOUT => CLK_28,
    HCLKIN => CLK,
    RESETN => PLL_LOCKED,
    CALIB => '1'
);

-- connect onboard BL616 console to hw pins for an USB-UART adapter
uart_tx <= bl616_mon_rx;
bl616_mon_tx <= uart_rx;

--reset_n <= (not KEY(0)) and PLL_LOCKED and SDRAM_RESET_N; -- jepalza, meto RESET externo y SDRAM_RESET_N
reset_n <= PLL_LOCKED and SDRAM_RESET_N; -- jepalza, meto RESET externo y SDRAM_RESET_N

-- HDMI
-- Recommended params:
-- N=6144 CTS=28333 (28.333MHz pixel clock -> 48KHz audio clock)
-- N=4096 CTS=28333 (28.333MHz pixel clock -> 32KHz audio clock)

-- inst_dvid: entity work.hdmi
-- generic map (
-- 	FREQ 		=> 28333333,
-- 	FS 		=> 48000,
-- 	N 		=> 6144,
-- 	CTS 		=> 28333)
-- port map(
-- 	I_CLK_VGA	=> CLK_PIXEL_IN,
-- 	I_CLK_TMDS	=> CLK_HDMI_IN,
-- 	I_HSYNC		=> not VIDEO_HS,
-- 	I_VSYNC		=> not VIDEO_VS,
-- 	I_BLANK		=> VIDEO_BLANK,
-- 	I_RED		=> VGA_R&"00",
-- 	I_GREEN		=> VGA_G&"00",
-- 	I_BLUE		=> VGA_B&"00",
-- 	I_AUDIO_PCM_L 	=> AUDIO_L_PCM,
-- 	I_AUDIO_PCM_R	=> AUDIO_L_PCM,
-- 	O_TMDS		=> HDMI);

	-- lcd_r <= VGA_R(5 downto 1) when pixel_enable = '1' else 5D"0";
	-- lcd_g <= VGA_G when pixel_enable = '1' else 6D"0";
	-- lcd_b <= VGA_B(5 downto 1) when pixel_enable = '1' else 5D"0";


-- display_controller_inst : entity work.lcd_ctrl
--     port map (
--       -- Clock and reset
--       clk   => CLK_28,
--       rst_n       => '1',
-- 	  ext_vsync => VGA_VS,
      
-- 	  lcd_clk => OPEN,   		--lcd pixel clock
-- 	  lcd_hs => lcd_hsync,	    	--lcd horizontal sync
-- 	  lcd_vs => lcd_vsync,	    	--lcd vertical sync
-- 	  lcd_de => lcd_de,			--lcd display enable; 1:Display Enable Signal;0: Disable Ddsplay

-- 	  lcd_r_in => VGA_R(5 downto 1),
-- 	  lcd_g_in => VGA_G,
-- 	  lcd_b_in => VGA_B(5 downto 1),

-- 	  lcd_r_out => lcd_r,
-- 	  lcd_g_out => lcd_g,
-- 	  lcd_b_out => lcd_b,

-- 	  lcd_xpos => OPEN,		--lcd horizontal coordinate
-- 	  lcd_ypos => OPEN,		--lcd vertical coordinate
-- 	  pixel_enable => pixel_enable

--     );


hdmi_ctrl_inst : entity work.hdmi_ctrl
 port map (
  clk_pixel_x5 => CLK_142,
  clk_pixel => CLK_28,
  rgb =>  "" & VGA_R & "00" & VGA_G & "00" & VGA_B & "00",
  AUDIO_R_PCM => AUDIO_R_PCM,
  AUDIO_L_PCM => AUDIO_L_PCM,

  pal_mode => '1',
  short_frame => '0',
  interlace => '0',
  reset => not(RESET_N) OR RESET_ATARI,    -- signal to synchronize HDMI

  tmds_clk_n => tmds_clk_n,
  tmds_clk_p => tmds_clk_p,
  tmds_d_n => tmds_d_n,
  tmds_d_p => tmds_d_p,

  cx => OPEN,
  cy => OPEN
);



-- display_controller_inst : entity work.complete_display_controller
--     generic map (
--       -- Configure for 800x480 LCD display
--       H_ACTIVE             => 800,    -- LCD horizontal resolution
--       V_ACTIVE             => 480,    -- LCD vertical resolution
      
--       -- Sync delays (adjust these to position the image)
--       HSYNC_DELAY_CYCLES   => 0,     -- Horizontal delay
--       VSYNC_DELAY_LINES    => 0,     -- Vertical delay
      
--       -- DE generation timing (adjust based on your display's requirements)
--       DE_H_START           => 88,     -- Typically the horizontal back porch
--       DE_V_START           => 32,     -- Typically the vertical back porch
      
--       -- Sync width configuration
--       USE_MEASURED_WIDTHS  => 1,      -- Enable automatic width measurement
--       FIXED_HSYNC_WIDTH    => 96,     -- Fallback hsync width
--       FIXED_VSYNC_WIDTH    => 2       -- Fallback vsync width
--     )
--     port map (
--       -- Clock and reset
--       clk_pixel   => CLK_28,
--       reset       => not(reset_n) OR RESET_ATARI,
      
--       -- Input from GTIA/ANTIC
--       vsync_in    => VGA_VS,
--       hsync_in    => VGA_HS,
--       red_in      => VGA_R(5 downto 1),
--       green_in    => VGA_G,
--       blue_in     => VGA_B(5 downto 1),
      
--       -- Output to LCD
--       vsync_out   => lcd_vsync,
--       hsync_out   => lcd_hsync,
--       de_out      => lcd_de,
--       red_out     => lcd_r,
--       green_out   => lcd_g,
--       blue_out    => lcd_b
--     );



-- sonido canal izquierdo
-- dac_l : hq_dac
-- port map
-- (
--   reset => not(reset_n),
--   clk => clk,
--   clk_ena => '1',
--   pcm_in => AUDIO_L_PCM&"0000",
--   dac_out => audio1_left -- audio_out_l
-- );
--audio1_left <= audio_out_l;

-- sonido canal derecho, jepalza
-- dac_r : hq_dac
-- port map
-- (
--   reset => not(reset_n),
--   clk => clk,
--   clk_ena => '1',
--   pcm_in => AUDIO_R_PCM&"0000",
--   dac_out => audio1_right --audio_out_r
-- );
--audio1_right <= audio_out_r;



-- JOY1_IN_N <=  (JOYA(4) xnor not (ps2_keys(16#171#) or ps2_keys(16#70#))) --real joy & numpad joy emulation.
-- 				& (JOYA(0) xnor not  ps2_keys(16#74#)) 
-- 				& (JOYA(1) xnor not  ps2_keys(16#6b#)) 
-- 				& (JOYA(2) xnor not (ps2_keys(16#72#)  or ps2_keys(16#73#))) 
-- 				& (JOYA(3) xnor not  ps2_keys(16#75#));

-- cursor keys joy emulation.
-- JOY1_IN_N <=  (NOT keyboard(110)) -- fire / button
-- 				& (NOT keyboard(79)) -- right
-- 				& (NOT keyboard(80)) -- left
-- 				& (NOT keyboard(81)) -- down
-- 				& (NOT keyboard(82)); -- up

JOY1_IN_N(4) <= '0' when keyboard(110)='1' or joystick0(5) = '1' else '1';
JOY1_IN_N(3) <= '0' when keyboard(79)='1' or joystick0(0) = '1' else '1';
JOY1_IN_N(2) <= '0' when keyboard(80)='1' or joystick0(1) = '1' else '1';
JOY1_IN_N(1) <= '0' when keyboard(81)='1' or joystick0(2) = '1' else '1';
JOY1_IN_N(0) <= '0' when keyboard(82)='1' or joystick0(3) = '1' or joystick0(6) = '1' else '1';

JOY2_IN_N(4) <= '1';
JOY2_IN_N(3) <= '1';
JOY2_IN_N(2) <= '1';
JOY2_IN_N(1) <= '1';
JOY2_IN_N(0) <= '1';


-- JOY2_IN_N <= JOYB(4) & JOYB(0) & JOYB(1) & JOYB(2) & JOYB(3);

--JOY1_IN_N <= JOYSTICK1_6&JOYSTICK1_4&JOYSTICK1_3&JOYSTICK1_2&JOYSTICK1_1;
--JOY2_IN_N <= JOYSTICK2_6&JOYSTICK2_4&JOYSTICK2_3&JOYSTICK2_2&JOYSTICK2_1;

-- USB to pokey
keyboard_map1 : entity work.usb_to_atari800
	GENERIC MAP
	(
		USB_enable => 1,
		direct_enable => 1
	)
	PORT MAP
	( 
		CLK => clk,
		RESET_N => reset_n,

		INPUT => zpu_out4,
		
		ATARI_KEYBOARD_OUT => atari_keyboard,
		USB_KEYBOARD => keyboard,
		joystick0 => joystick0,
		joystick0_console => joystick0_console,
		

		KEYBOARD_SCAN => KEYBOARD_SCAN,
		KEYBOARD_RESPONSE => KEYBOARD_RESPONSE,

		CONSOL_START => CONSOL_START,
		CONSOL_SELECT => CONSOL_SELECT,
		CONSOL_OPTION => CONSOL_OPTION,
		
		FKEYS => FKEYS,
		FREEZER_ACTIVATE => freezer_activate,

		USB_KEYS_NEXT_OUT => USB_KEYS_NEXT,
		USB_KEYS => USB_KEYS
		--,MRESET => REBOOT -- jepalza, anulo
	);

-- FKEYS(11) <= '1' WHEN KEY(1) = '1' ELSE '0';
-- CONSOL_OPTION <= '1' WHEN KEY(1) = '1' ELSE '0';
-- CONSOL_START <= '1' WHEN KEY(0) = '1' ELSE '0';

atarixl_simple_sdram1 : entity work.atari800core_simple_sdram
	GENERIC MAP
	(
		cycle_length => 32,
		internal_rom => internal_rom,
		internal_ram => internal_ram,
		video_bits   => 8,
		palette      => 0,
		low_memory   => 0, -- jepalza --> 0=8mb, 1=1mb, 2=512k?
      --STEREO       => 1,
      COVOX        => 1
	)
	PORT MAP
	(
		CLK => CLK,
		RESET_N => RESET_N and not(RESET_ATARI),

		VIDEO_VS => VIDEO_VS,
		VIDEO_HS => VIDEO_HS,
		VIDEO_CS => VIDEO_CS,
		VIDEO_B => VIDEO_B,
		VIDEO_G => VIDEO_G,
		VIDEO_R => VIDEO_R,
		VIDEO_BLANK =>VIDEO_BLANK,
		VIDEO_BURST =>VIDEO_BURST,
		VIDEO_START_OF_FIELD =>VIDEO_START_OF_FIELD,
		VIDEO_ODD_LINE =>VIDEO_ODD_LINE,

		STEREO => '1',
		AUDIO_L => AUDIO_L_PCM,
		AUDIO_R => AUDIO_R_PCM,

		JOY1_n => JOY1_IN_N, -- este puerto, ademas, emula mando con teclado
		JOY2_n => JOY2_IN_N, 

		KEYBOARD_RESPONSE => KEYBOARD_RESPONSE,
		KEYBOARD_SCAN => KEYBOARD_SCAN,

		SIO_COMMAND => zpu_sio_command,
		SIO_RXD => zpu_sio_txd,
		SIO_TXD => zpu_sio_rxd,
		SIO_CLOCKOUT => ASIO_CLOCKOUT,

		CONSOL_OPTION => CONSOL_OPTION,
		CONSOL_SELECT => CONSOL_SELECT,
		CONSOL_START => CONSOL_START,

-- TODO, connect to SRAM! Handle 32-bit in multiple cycles. How fast is the sram.
		SDRAM_REQUEST => ram_request,
		SDRAM_REQUEST_COMPLETE => ram_request_complete,
		SDRAM_READ_ENABLE => ram_read_enable,
		SDRAM_WRITE_ENABLE => ram_write_enable,
		SDRAM_ADDR => ram_addr,
		SDRAM_DO => ram_do,
		SDRAM_DI => ram_di,
		SDRAM_REFRESH => ram_refresh, -- jepalza
		SDRAM_32BIT_WRITE_ENABLE => SDRAM_WIDTH_32BIT_ACCESS, -- jepalza
		SDRAM_16BIT_WRITE_ENABLE => SDRAM_WIDTH_16BIT_ACCESS, -- jepalza
		SDRAM_8BIT_WRITE_ENABLE => SDRAM_WIDTH_8BIT_ACCESS, -- jepalza

		DMA_FETCH => DMA_FETCH,
		DMA_READ_ENABLE => DMA_READ_ENABLE,
		DMA_32BIT_WRITE_ENABLE => DMA_32BIT_WRITE_ENABLE,
		DMA_16BIT_WRITE_ENABLE => DMA_16BIT_WRITE_ENABLE,
		DMA_8BIT_WRITE_ENABLE => DMA_8BIT_WRITE_ENABLE,
		DMA_ADDR => DMA_ADDR_FETCH,
		DMA_WRITE_DATA => DMA_WRITE_DATA,
		MEMORY_READY_DMA => DMA_MEMORY_READY,
		DMA_MEMORY_DATA => DMA_MEMORY_DATA, 

   	RAM_SELECT => ram_select,
		PAL => PAL,
		HALT => pause_atari,
		THROTTLE_COUNT_6502 => speed_6502,
		TURBO_VBLANK_ONLY => turbo_vblank_only,
		ATARI800MODE => atari800mode,
		emulated_cartridge_select => emulated_cartridge_select,
--		freezer_enable => freezer_enable,
--		freezer_activate => freezer_activate
		freezer_enable => '0',
		freezer_activate => '0'
	);


scandoubler_ctrl <= '1';--ram_do(0); -- jepalza, no se si vale asi

-- jepalza, SDRAM desde Reverse U16
sdram_adaptor : entity work.sdram_statemachine
GENERIC MAP(ADDRESS_WIDTH => 22, -- toda la RAM posible: 24-0 son 32mb !!!!
			AP_BIT => 10,
			COLUMN_WIDTH => 8,
			ROW_WIDTH => 11 -- nuestra SDRAM tiene 12 a 0 (13)
			)
PORT MAP(
	    CLK_SYSTEM => CLK, --ATARI_CLK,
		 CLK_SDRAM => CLK_SDRAM_IN, -- 113.28mhz necesarios, pero le paso 114.28
		 RESET_N => '1',--NOT KEY(0), -- reset externo por boton
		 REQUEST => ram_request,
		 READ_EN => ram_read_enable,
		 WRITE_EN => ram_write_enable,
		 BYTE_ACCESS => SDRAM_WIDTH_8BIT_ACCESS,
		 WORD_ACCESS => SDRAM_WIDTH_16BIT_ACCESS,
		 LONGWORD_ACCESS => SDRAM_WIDTH_32BIT_ACCESS,
		 REFRESH => ram_refresh,
		 COMPLETE => ram_request_complete,
		 -- modulo SRAM "emulado"
		 --ADDRESS_IN => "00"&"0000"&ram_addr(18 downto 0), -- jepalza, compatible zxuno 512k (solo 320k de ampliacion)
		 --ADDRESS_IN => "00"&ram_addr, -- jepalza, 8mb de ram , entrada 24-0 , pero ram_addr solo 22-0
		 		 ADDRESS_IN => ram_addr, -- jepalza, 8mb de ram , entrada 24-0 , pero ram_addr solo 22-0
		 DATA_IN => ram_di,
		 DATA_OUT => ram_do,
		 -- Acceso SDRAM externa
		 SDRAM_DQ => IO_sdram_dq,
		 SDRAM_BA0 => O_sdram_ba(0),
		 SDRAM_BA1 => O_sdram_ba(1),
		 SDRAM_CKE => O_sdram_cke, -- jepalza, antes no estaba
		 SDRAM_CS_N => O_sdram_cs_n, -- jepalza, idem
		 SDRAM_RAS_N => O_sdram_ras_n,
		 SDRAM_CAS_N => O_sdram_cas_n,
		 SDRAM_WE_N => O_sdram_wen_n,
		 SDRAM_ldqm => O_sdram_dqm(0),
		 SDRAM_udqm => O_sdram_dqm(1),
		 SDRAM_ldqm1 => O_sdram_dqm(2),
		 SDRAM_udqm1 => O_sdram_dqm(3),
		 SDRAM_ADDR => O_sdram_addr, --(12 downto 0), no es necesario
		 --
		 reset_client_n => SDRAM_RESET_N
		 );


-- jepalza, alternativo funciona, pero que lo haga el modulo SDRAM
--SDRAM_CKE <= '1';
--SDRAM_CS_N <= '0';

-- Video options
	PAL <= not VIDEOSTD;
	
--	O_NTSC <= not PAL;
--	O_PAL  <= PAL;
	
	-- Key combos for zxuno
	process (clk) 
	begin
	if (clk'event and clk='1') then
		-- scrolLock RGB/VGA
		if (VIDEOSW = '0' and (not(ps2_keys(16#7e#)) and ps2_keys_next(16#7e#)) = '1'  ) then
			--vga <= '1';
			--composite_on_hsync <= '0';
			--VIDEOSW <= '1';
		elsif (VIDEOSW = '1' and (not(ps2_keys(16#7e#)) and ps2_keys_next(16#7e#)) = '1') then
			--vga <= '0';
			--composite_on_hsync <= '1';
			--VIDEOSW <= '0';
		end if;	
		
		--"*" PAL / NTSC
		-- if (VIDEOSTD = '0'  and USB_KEYS_NEXT(76) = '1'  ) then
		-- 	VIDEOSTD <= '1';
		-- elsif (VIDEOSTD = '1' and USB_KEYS_NEXT(76) = '1') then
		-- 	VIDEOSTD <= '0';
		-- end if;					
	 end if; 
	end process;

	process(clk,RESET_N,reset_atari)
	begin
		if ((RESET_N and not(reset_atari))='0') then
			half_scandouble_enable_reg <= '0';
			scanlines_reg <= '1';
		elsif (clk'event and clk='1') then
			half_scandouble_enable_reg <= half_scandouble_enable_next;
			scanlines_reg <= scanlines_next;
		end if;
	end process;

	half_scandouble_enable_next <= not(half_scandouble_enable_reg);
	
	scanlines_next <= scanlines_reg xor (not(ps2_keys(16#7b#)) and ps2_keys_next(16#7b#)); -- left alt

	scandoubler1: entity work.scandoubler
	PORT MAP
	( 
		CLK => CLK,
	   RESET_N => reset_n,
		
		VGA => '1',--scandoubler_ctrl xor vga,
		COMPOSITE_ON_HSYNC => scandoubler_ctrl xor composite_on_hsync,

		colour_enable => half_scandouble_enable_reg,
		doubled_enable => '1',
		scanlines_on => scanlines_reg,
		
		-- GTIA interface
		pal => PAL,
		colour_in => VIDEO_B,
		vsync_in => VIDEO_VS,
		hsync_in => VIDEO_HS,
		csync_in => VIDEO_CS,
		
		-- TO TV...
		R => VGA_R(5 downto 2),
		G => VGA_G(5 downto 2),
		B => VGA_B(5 downto 2),
		
		VSYNC => VGA_VS,
		HSYNC => VGA_HS
	);

--VGA_R <= VGA_R4 & "00";
--VGA_G <= VGA_G4 & "00";
--VGA_B <= VGA_B4 & "00";

zpu: entity work.zpucore
	GENERIC MAP
	(
		platform => 1,
		spi_clock_div => 2, -- 28MHz/2. Max for SD cards is 25MHz...
		usb => 0
	)
	PORT MAP
	(
		-- standard...
		CLK => CLK,
		RESET_N => RESET_N and SDRAM_RESET_N, -- jepalza incluyo SDRAM_RESET_N

		-- dma bus master (with many waitstates...)
		ZPU_ADDR_FETCH => DMA_ADDR_FETCH,
		ZPU_DATA_OUT => DMA_WRITE_DATA,
		ZPU_FETCH => DMA_FETCH,
		ZPU_32BIT_WRITE_ENABLE => DMA_32BIT_WRITE_ENABLE,
		ZPU_16BIT_WRITE_ENABLE => DMA_16BIT_WRITE_ENABLE,
		ZPU_8BIT_WRITE_ENABLE => DMA_8BIT_WRITE_ENABLE,
		ZPU_READ_ENABLE => DMA_READ_ENABLE,
		ZPU_MEMORY_READY => DMA_MEMORY_READY,
		ZPU_MEMORY_DATA => DMA_MEMORY_DATA, 

		-- rom bus master
		-- data on next cycle after addr
		ZPU_ADDR_ROM => zpu_addr_rom,
		ZPU_ROM_DATA => zpu_rom_data,

		-- spi master
		-- Too painful to bit bang spi from zpu, so we have a hardware master in here
		ZPU_SD_DAT0 => SD_MISO,
		ZPU_SD_CLK => SD_SCK,
		ZPU_SD_CMD => SD_MOSI,
		ZPU_SD_DAT3 => SD_nCS,

		-- SIO
		-- Ditto for speaking to Atari, we have a built in Pokey
		ZPU_POKEY_ENABLE => zpu_pokey_enable,
		ZPU_SIO_TXD => zpu_sio_txd,
		ZPU_SIO_RXD => zpu_sio_rxd,
		ZPU_SIO_COMMAND => zpu_sio_command,

		-- external control
		-- switches etc. sector DMA blah blah.
		ZPU_IN1 => X"000"&
			"00"& 
			(USB_KEYS_NEXT(41) OR joystick0_console(3)) &
			USB_KEYS_NEXT(40) &
			USB_KEYS_NEXT(79) & 
			USB_KEYS_NEXT(80) & 
			USB_KEYS_NEXT(81) & 
			USB_KEYS_NEXT(82) & 
			-- (esc)FLRDU
			FKEYS,
		ZPU_IN2 => X"00000000",
		ZPU_IN3 => X"00000000",
		ZPU_IN4 => X"00000000",

		-- ouputs - e.g. Atari system control, halt, throttle, rom select
		ZPU_OUT1 => zpu_out1,
		ZPU_OUT2 => zpu_out2, --joy0
		ZPU_OUT3 => zpu_out3, --joy1
		ZPU_OUT4 => zpu_out4, --keyboard
		ZPU_OUT5 => zpu_out5  --analog stick (not supported without USB)
	);

	pause_atari <= zpu_out1(0);
	reset_atari <= zpu_out1(1);
	speed_6502 <= zpu_out1(7 downto 2);
	ram_select <= zpu_out1(10 downto 8);
	atari800mode <= '0';
	emulated_cartridge_select <= zpu_out1(22 downto 17);
	freezer_enable <= zpu_out1(25);

	turbo_vblank_only <= '0';


zpu_rom1: entity work.zpu_rom
	port map(
	        clock => clk,
	        address => zpu_addr_rom(13 downto 2),
	        q => zpu_rom_data
	);

enable_179_clock_div_zpu_pokey : entity work.enable_divider
	generic map (COUNT=>32) -- cycle_length
	port map(clk=>clk,reset_n=>reset_n,enable_in=>'1',enable_out=>zpu_pokey_enable);
	
LEDS(0) <= not(VIDEOSTD);
LEDS(1) <= not(DMA_MEMORY_READY);
LEDS(2) <= not(DMA_FETCH); 	

fpga_companion_inst : entity work.fpga_companion
	port map (
    clk => CLK_28,
    reset => not(reset_n),

    --interface to external FPGA companion
    m0s => m0s,

	spi_sclk => spi_sclk, 
	spi_csn => spi_csn, 
	spi_dir => spi_dir,
	spi_dat => spi_dat, 
	spi_irqn => spi_irqn,

    --USB keyboard data
	keyboard => keyboard,
	joystick0 => joystick0,
	joystick0_console => joystick0_console,
	joystick1 => joystick1,

	--RGB LED
    ws2812_color =>  ws2812_color
);

-- connect to ws2812 led

ws2812_inst : entity work.ws2812
	port map (
    clk => CLK_28,
	color => ws2812_color,--"000000000000000011111111",
    ws2812 => WS_2812
);

-- i2s_inst : entity work.i2s
-- 	port map (
-- 		clk => CLK_28,
-- 		reset => not(reset_n),
-- 		AUDIO_L_PCM => AUDIO_L_PCM,
-- 		AUDIO_R_PCM => AUDIO_R_PCM,
-- 		pa_en => pa_en,
--     	hp_bck => hp_bck,
--      	hp_ws => hp_ws,
--     	hp_din => hp_din
-- 	);

END vhdl;
