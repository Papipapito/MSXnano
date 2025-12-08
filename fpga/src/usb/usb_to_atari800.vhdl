---------------------------------------------------------------------------
-- (c) 2013 mark watson
-- I am happy for anyone to use this for non-commercial use.
-- If my vhdl files are used commercially or otherwise sold,
-- please contact me for explicit permission at scrameta (gmail).
-- This applies for source and binary form and derived works.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- (ILoveSpeccy) Added PS2_KEYS Output
---------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.numeric_std.all;


ENTITY usb_to_atari800 IS
GENERIC
(
	USB_enable : integer := 1;
	direct_enable : integer := 0
);
PORT 
( 
	CLK : IN STD_LOGIC;
	RESET_N : IN STD_LOGIC;
	USB_KEYBOARD : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
	joystick0 : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
	joystick0_console : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
	INPUT : IN STD_LOGIC_VECTOR(31 downto 0) := (others=>'0');
	
	KEYBOARD_SCAN : IN STD_LOGIC_VECTOR(5 downto 0);
	KEYBOARD_RESPONSE : OUT STD_LOGIC_VECTOR(1 downto 0);

	CONSOL_START : OUT STD_LOGIC;
	CONSOL_SELECT : OUT STD_LOGIC;
	CONSOL_OPTION : OUT STD_LOGIC;
   
	FKEYS : OUT STD_LOGIC_VECTOR(11 downto 0);

	FREEZER_ACTIVATE : OUT STD_LOGIC;

	USB_KEYS : OUT STD_LOGIC_VECTOR(127 downto 0);
	USB_KEYS_NEXT_OUT : OUT STD_LOGIC_VECTOR(127 downto 0);
	ATARI_KEYBOARD_OUT : OUT STD_LOGIC_VECTOR(63 downto 0)
   
);
END usb_to_atari800;

ARCHITECTURE vhdl OF usb_to_atari800 IS
	signal USB_keys_next : std_logic_vector(127 downto 0);
	signal USB_keys_reg : std_logic_vector(127 downto 0);


	signal CONSOL_START_INT : std_logic;
	signal CONSOL_SELECT_INT : std_logic;
	signal CONSOL_OPTION_INT : std_logic;

	signal FKEYS_INT : std_logic_vector(11 downto 0);

	signal FREEZER_ACTIVATE_INT : std_logic;

	signal atari_keyboard : std_logic_vector(63 downto 0);
	SIGNAL	SHIFT_PRESSED :  STD_LOGIC;
	SIGNAL	BREAK_PRESSED :  STD_LOGIC;
	SIGNAL	CONTROL_PRESSED :  STD_LOGIC;
BEGIN
	process(clk,reset_n)
	begin
		if (reset_n='0') then
			USB_keys_reg <= (others=>'0');
		elsif (clk'event and clk='1') then
			USB_keys_reg <= USB_KEYBOARD;
		end if;
	end process;

	process(USB_keys_reg)
	begin
		USB_keys_next <= USB_keys_reg;
	end process;

	-- map to atari key code
	process(USB_keys_reg)
	begin
		atari_keyboard <= (others=>'0');

		shift_pressed <= '0';
		control_pressed <= '0';
		break_pressed <= '0';
		consol_start_int <= '0';
		consol_select_int <= '0';
		consol_option_int <= '0';

atari_keyboard(63)<=USB_KEYBOARD(04);  -- keycap: A, USB code: 04
atari_keyboard(21)<=USB_KEYBOARD(05);  -- keycap: B, USB code: 05 
atari_keyboard(18)<=USB_KEYBOARD(06);  -- keycap: C, USB code: 06
atari_keyboard(58)<=USB_KEYBOARD(07);  -- keycap: D, USB code: 07
atari_keyboard(42)<=USB_KEYBOARD(8);  -- keycap: E, USB code: 08
atari_keyboard(56)<=USB_KEYBOARD(9);  -- keycap: F, USB code: 09
atari_keyboard(61)<=USB_KEYBOARD(10);  -- keycap: G, USB code: 0A
atari_keyboard(57)<=USB_KEYBOARD(11);  -- keycap: H, USB code: 0B
atari_keyboard(13)<=USB_KEYBOARD(12);  -- keycap: I, USB code: 0C
atari_keyboard(1)<=USB_KEYBOARD(13);   -- keycap: J, USB code: 0D
atari_keyboard(5)<=USB_KEYBOARD(14);   -- keycap: K, USB code: 0E
atari_keyboard(0)<=USB_KEYBOARD(15);   -- keycap: L, USB code: 0F
atari_keyboard(37)<=USB_KEYBOARD(16);  -- keycap: M, USB code: 10
atari_keyboard(35)<=USB_KEYBOARD(17);  -- keycap: N, USB code: 11
atari_keyboard(8)<=USB_KEYBOARD(18);   -- keycap: O, USB code: 12
atari_keyboard(10)<=USB_KEYBOARD(19);  -- keycap: P, USB code: 13
atari_keyboard(47)<=USB_KEYBOARD(20);  -- keycap: Q, USB code: 14
atari_keyboard(40)<=USB_KEYBOARD(21);  -- keycap: R, USB code: 15
atari_keyboard(62)<=USB_KEYBOARD(22);  -- keycap: S, USB code: 16
atari_keyboard(45)<=USB_KEYBOARD(23);  -- keycap: T, USB code: 17
atari_keyboard(11)<=USB_KEYBOARD(24);  -- keycap: U, USB code: 18
atari_keyboard(16)<=USB_KEYBOARD(25);  -- keycap: V, USB code: 19
atari_keyboard(46)<=USB_KEYBOARD(26);  -- keycap: W, USB code: 1A
atari_keyboard(22)<=USB_KEYBOARD(27);  -- keycap: X, USB code: 1B
atari_keyboard(43)<=USB_KEYBOARD(28);  -- keycap: Y, USB code: 1C
atari_keyboard(23)<=USB_KEYBOARD(29);  -- keycap: Z, USB code: 1D
atari_keyboard(50)<=USB_KEYBOARD(39);  -- keycap: 0 ), USB code: 27
atari_keyboard(31)<=USB_KEYBOARD(30);  -- keycap: 1 !, USB code: 1E
atari_keyboard(30)<=USB_KEYBOARD(31);  -- keycap: 2 @, USB code: 1F
atari_keyboard(26)<=USB_KEYBOARD(32);  -- keycap: 3 #, USB code: 20
atari_keyboard(24)<=USB_KEYBOARD(33);  -- keycap: 4 $, USB code: 21
atari_keyboard(29)<=USB_KEYBOARD(34);  -- keycap: 5 %, USB code: 22
atari_keyboard(27)<=USB_KEYBOARD(35);  -- keycap: 6 ^, USB code: 23
atari_keyboard(51)<=USB_KEYBOARD(36);  -- keycap: 7 &, USB code: 24
atari_keyboard(53)<=USB_KEYBOARD(37);  -- keycap: 8 *, USB code: 25
atari_keyboard(48)<=USB_KEYBOARD(38);  -- keycap: 9 (, USB code: 26
--atari_keyboard(17)<=USB_KEYBOARD(0);  -- (Commented out) E0,C - Extended code
--atari_keyboard(17)<=USB_KEYBOARD(0); -- (Commented out) E0,6C - Extended code Home
atari_keyboard(17)<=USB_KEYBOARD(0) or USB_KEYBOARD(0);  -- E0,6C (Home) or 03 (F5), USB codes: 74/62
atari_keyboard(52)<=USB_KEYBOARD(42);  -- keycap: Backspace, USB code: 2A
atari_keyboard(28)<=USB_KEYBOARD(41);  -- keycap: Esc, USB code: 29
--atari_keyboard(39)<=USB_KEYBOARD(0);  -- (Commented out) - Extended code
atari_keyboard(39)<=USB_KEYBOARD(0); -- E0,11 - Extended code RAlt, USB code: 230
atari_keyboard(60)<=USB_KEYBOARD(57);  -- keycap: Caps Lock, USB code: 39
atari_keyboard(44)<=USB_KEYBOARD(43);  -- keycap: Tab, USB code: 2B
atari_keyboard(12)<=USB_KEYBOARD(40);  -- keycap: Enter, USB code: 28
atari_keyboard(33)<=USB_KEYBOARD(44);  -- keycap: Space, USB code: 2C
atari_keyboard(54)<=USB_KEYBOARD(45);  -- keycap: - _, USB code: 2D
atari_keyboard(55)<=USB_KEYBOARD(46);  -- keycap: = +, USB code: 2E
atari_keyboard(15)<=USB_KEYBOARD(48);  -- keycap: ] }, USB code: 30
atari_keyboard(14)<=USB_KEYBOARD(47);  -- keycap: [ {, USB code: 2F
atari_keyboard(6)<=USB_KEYBOARD(52);   -- keycap: Up Arrow, USB code: 52
atari_keyboard(7)<=USB_KEYBOARD(49);   -- keycap: \ |, USB code: 31
atari_keyboard(38)<=USB_KEYBOARD(56);  -- keycap: / ?, USB code: 38
atari_keyboard(2)<=USB_KEYBOARD(51);   -- keycap: ; :, USB code: 33
atari_keyboard(32)<=USB_KEYBOARD(54);  -- keycap: , <, USB code: 36
atari_keyboard(34)<=USB_KEYBOARD(55);  -- keycap: . >, USB code: 37

-- Function keys
atari_keyboard(3)<=USB_KEYBOARD(58);   -- keycap: F1, USB code: 3A
atari_keyboard(4)<=USB_KEYBOARD(59);   -- keycap: F2, USB code: 3B
atari_keyboard(19)<=USB_KEYBOARD(60);  -- keycap: F3, USB code: 3C
atari_keyboard(20)<=USB_KEYBOARD(61);  -- keycap: F4, USB code: 3D

-- Console and special keys
consol_start_int<=USB_KEYBOARD(62) OR joystick0(4);    -- keycap: F6, USB code: 3F
consol_select_int<=USB_KEYBOARD(63) OR joystick0(7);   -- keycap: F7, USB code: 40
consol_option_int<=USB_KEYBOARD(64) OR joystick0_console(1);   -- keycap: F5, USB code: 3E
shift_pressed<=USB_KEYBOARD(105) or USB_KEYBOARD(109);  -- Left Shift (12) or Right Shift (59), USB codes: E1, E5
--control_pressed<=USB_KEYBOARD(0) or keyboard(0);  -- (Commented out) - Left Ctrl or Extended Right Ctrl
control_pressed<=USB_KEYBOARD(104) or USB_KEYBOARD(0);  -- Left Ctrl (14) or Extended Right Ctrl (E0,14), USB codes: E0, E4
break_pressed<=USB_KEYBOARD(0);       -- keycap: Num Lock, USB code: 53

-- Function keys mapping
fkeys_int(0)<=USB_KEYBOARD(58);        -- keycap: F1, USB code: 3A
fkeys_int(1)<=USB_KEYBOARD(59);        -- keycap: F2, USB code: 3B
fkeys_int(2)<=USB_KEYBOARD(60);        -- keycap: F3, USB code: 3C
fkeys_int(3)<=USB_KEYBOARD(61);        -- keycap: F4, USB code: 3D
fkeys_int(4)<=USB_KEYBOARD(62);        -- keycap: F5, USB code: 3E
fkeys_int(5)<=USB_KEYBOARD(63);        -- keycap: F6, USB code: 3F
fkeys_int(6)<=USB_KEYBOARD(64);        -- keycap: F7, USB code: 40
fkeys_int(7)<=USB_KEYBOARD(65);        -- keycap: F5 (duplicate), USB code: 3E
fkeys_int(8)<=USB_KEYBOARD(66);        -- keycap: F9, USB code: 42
fkeys_int(9)<=USB_KEYBOARD(67) OR joystick0_console(0);        -- keycap: F10, USB code: 43
fkeys_int(10)<=USB_KEYBOARD(0); --69      -- keycap: F11, USB code: 44
fkeys_int(11)<=USB_KEYBOARD(76) OR joystick0_console(2); --was 68      -- keycap: DEL
		-- use scroll lock or delete to activate freezer (same key on my keyboard + scroll lock does not seem to work on mist!)
		freezer_activate_int <= USB_KEYBOARD(0) or USB_KEYBOARD(0);
	end process;

	-- provide results as if we were a grid to pokey...
	process(keyboard_scan, atari_keyboard, control_pressed, shift_pressed, break_pressed)
		begin	
			keyboard_response <= (others=>'1');		
			
			if (atari_keyboard(to_integer(unsigned(not(keyboard_scan)))) = '1') then
				keyboard_response(0) <= '0';
			end if;
			
			if (keyboard_scan(5 downto 4)="00" and break_pressed = '1') then
				keyboard_response(1) <= '0';
			end if;
			
			if (keyboard_scan(5 downto 4)="10" and shift_pressed = '1') then
				keyboard_response(1) <= '0';
			end if;

			if (keyboard_scan(5 downto 4)="11" and control_pressed = '1') then
				keyboard_response(1) <= '0';
			end if;
	end process;		 

	-- outputs
	CONSOL_START <= CONSOL_START_INT;
	CONSOL_SELECT <= CONSOL_SELECT_INT;
	CONSOL_OPTION <= CONSOL_OPTION_INT;

	FKEYS <= FKEYS_INT;
	FREEZER_ACTIVATE <= FREEZER_ACTIVATE_INT;

	USB_KEYS <= USB_keys_reg;
	USB_KEYS_NEXT_OUT <= USB_keys_next;
	
	ATARI_KEYBOARD_OUT <= atari_keyboard;
END vhdl;

