library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library UNISIM;
use UNISIM.Vcomponents.ALL;

entity zynq_top is
  port (
    PL_CLK       : in std_logic;
    PL_LED1      : out std_logic;  -- Carrier D6
    PL_LED2      : out std_logic;  -- Carrier D7
    PL_LED3      : out std_logic;  -- Carrier D8
    PL_LED4      : out std_logic;  -- Carrier D9

    PL_PB1       : in std_logic;   -- JX1 pin 19,  Zynq G2, Carrier SW1 N
    PL_PB2       : in std_logic;   -- JX2 pin 100, Zynq T16, Carrier SW5 S
    PL_PB3       : in std_logic;   -- JX2 pin 95,  Zynq AB22, Carrier SW3, E
    PL_PB4       : in std_logic;   -- JX2 pin 94,  Zynq AB18, Carrier SW2, W
    PL_PB5       : in std_logic;   -- JX2 pin 96,  Zynq AB19, Carrier SW4, C

    BANK13_LVDS_8_P : out std_logic;
    BANK13_LVDS_8_N : out std_logic;
    
    MGTREFCLK1_P : in std_logic;   -- JX3 pin 2,   Zynq U5
    MGTREFCLK1_N : in std_logic;   -- JX3 pin 3,   Zynq V5

    MGTTX2_P     : out std_logic;  -- JX3 pin 25,  Zynq AA5
    MGTTX2_N     : out std_logic;  -- JX3 pin 27,  Zynq AB5
    MGTRX2_P     : in std_logic;   -- JX3 pin 20,  Zynq AA9
    MGTRX2_N     : in std_logic    -- JX3 pin 22,  Zynq AB9
    );
end zynq_top;

architecture structure of zynq_top is

  component evr_dc is
      generic (
    -- MGT RX&TX signal pair polarity
    RX_POLARITY                  : std_logic := '0'; -- '1' for inverted polarity
    TX_POLARITY                  : std_logic := '0'; -- '1' for inverted polarity
    -- MGT reference clock selection
    REFCLKSEL                    : std_logic := '0' -- 0 - REFCLK0, 1 - REFCLK1
    );
  port (
    -- System bus clock
    sys_clk         : in std_logic;
    refclk_out      : out std_logic; -- Reference clock output
    event_clk_out   : out std_logic; -- Event clock output, delay compensated
				     -- and locked to EVG

    -- Receiver side connections
    event_rxd       : out std_logic_vector(7 downto 0);  -- Received event code
    dbus_rxd        : out std_logic_vector(7 downto 0);  -- Distributed bus data
    databuf_rxd     : out std_logic_vector(7 downto 0);  -- Databuffer data
    databuf_rx_k    : out std_logic; -- Databuffer K-character
    databuf_rx_ena  : out std_logic; -- Databuf data enable
    databuf_rx_mode : in std_logic;  -- Databuf receive mode, '1' enabled, '0'
				     -- disabled (only for non-DC)
    dc_mode         : in std_logic;  -- Delay compensation mode enable
      
    rx_link_ok      : out   std_logic; -- Received link ok
    rx_violation    : out   std_logic; -- Receiver violation detected
    rx_clear_viol   : in    std_logic; -- Clear receiver violatio flag
      
    -- Transmitter side connections
    event_txd       : in  std_logic_vector(7 downto 0); -- TX event code
    dbus_txd        : in  std_logic_vector(7 downto 0); -- TX distributed bus data
    databuf_txd     : in  std_logic_vector(7 downto 0); -- TX databuffer data
    databuf_tx_k    : in  std_logic; -- TX databuffer K-character
    databuf_tx_ena  : out std_logic; -- TX databuffer data enable
    databuf_tx_mode : in  std_logic; -- TX databuffer transmit mode, '1'
				     -- enabled, '0' disabled

    reset           : in  std_logic; -- Transmitter reset

    -- Delay compensation signals
    delay_comp_update : in std_logic;
    delay_comp_value  : in std_logic_vector(31 downto 0);
    delay_comp_target : in std_logic_vector(31 downto 0);
    delay_comp_locked_out : out std_logic;

    -- MGT physical pins
    
    MGTREFCLK0_P : in std_logic;
    MGTREFCLK0_N : in std_logic;
    MGTREFCLK1_P : in std_logic;   -- JX3 pin 2,   Zynq U5
    MGTREFCLK1_N : in std_logic;   -- JX3 pin 3,   Zynq V5

    MGTTX2_P     : out std_logic;  -- JX3 pin 25,  Zynq AA5
    MGTTX2_N     : out std_logic;  -- JX3 pin 27,  Zynq AB5
    MGTRX2_P     : in std_logic;   -- JX3 pin 20,  Zynq AA9
    MGTRX2_N     : in std_logic    -- JX3 pin 22,  Zynq AB9
    );
  end component;

  component databuf_rx_dc is
    port (
      -- Memory buffer RAMB read interface
      data_out          : out std_logic_vector(31 downto 0);
      size_data_out     : out std_logic_vector(31 downto 0);
      addr_in           : in std_logic_vector(10 downto 2);
      clk               : in std_logic;
      
      -- Data stream interface
      databuf_data      : in std_logic_vector(7 downto 0);
      databuf_k         : in std_logic;
      databuf_ena       : in std_logic;
      event_clk         : in std_logic;
      
      delay_comp_update : out std_logic;
      delay_comp_rx     : out std_logic_vector(31 downto 0);
      delay_comp_status : out std_logic_vector(31 downto 0);
      topology_addr     : out std_logic_vector(31 downto 0);

      -- Control interface
      irq_out           : out std_logic;

      sirq_ena          : in std_logic_vector(0 to 127);
      rx_flag           : out std_logic_vector(0 to 127);
      cs_flag           : out std_logic_vector(0 to 127);
      ov_flag           : out std_logic_vector(0 to 127);
      clear_flag        : in std_logic_vector(0 to 127);
      
      reset             : in std_logic);
  end component;

  COMPONENT ila_0
    PORT (
      clk : IN STD_LOGIC;
      probe0 : IN STD_LOGIC_VECTOR(255 DOWNTO 0)
      );
  END COMPONENT;

  signal TRIG0 : std_logic_vector(255 downto 0);

  signal gnd     : std_logic;
  signal vcc     : std_logic;
  
  signal sys_clk : std_logic;
  signal sys_reset : std_logic;

  signal refclk  : std_logic;
  signal event_clk : std_logic;

  signal dc_mode         : std_logic;

  signal tx_reset : std_logic;
  
  signal event_link_ok : std_logic;

  signal event_rxd       : std_logic_vector(7 downto 0);
  signal dbus_rxd        : std_logic_vector(7 downto 0);
  signal databuf_rxd     : std_logic_vector(7 downto 0);
  signal databuf_rx_k    : std_logic;
  signal databuf_rx_ena  : std_logic;
  signal databuf_rx_mode : std_logic;
    
  signal rx_link_ok      : std_logic;
  signal rx_violation    : std_logic;
  signal rx_clear_viol   : std_logic;

  signal event_txd       : std_logic_vector(7 downto 0);
  signal dbus_txd        : std_logic_vector(7 downto 0);
  signal databuf_txd     : std_logic_vector(7 downto 0);
  signal databuf_tx_k    : std_logic;
  signal databuf_tx_ena  : std_logic;
  signal databuf_tx_mode : std_logic;

  signal delay_comp_locked  : std_logic;
  signal delay_comp_update  : std_logic;
  signal delay_comp_value   : std_logic_vector(31 downto 0);
  signal delay_comp_target  : std_logic_vector(31 downto 0);

  signal dc_status             : std_logic_vector(31 downto 0);
  signal delay_comp_rx_status : std_logic_vector(31 downto 0);

  signal databuf_dc_addr     : std_logic_vector(10 downto 2);
  signal databuf_dc_data_out : std_logic_vector(31 downto 0);
  signal databuf_dc_size_out : std_logic_vector(31 downto 0);
  signal databuf_sirq_ena    : std_logic_vector(0 to 127);
  signal databuf_rx_flag     : std_logic_vector(0 to 127);
  signal databuf_cs_flag     : std_logic_vector(0 to 127);
  signal databuf_ov_flag     : std_logic_vector(0 to 127);
  signal databuf_clear_flag  : std_logic_vector(0 to 127);
  signal databuf_irq_dc      : std_logic;

  signal topology_addr       : std_logic_vector(31 downto 0);
  
begin

  -- ILA debug core
  i_ila : ila_0
    port map (
      CLK => event_clk,
      probe0 => TRIG0);

  i_bufg : bufg
    port map (
      I => PL_CLK,
      O => sys_clk);

  i_evr_dc : evr_dc
    generic map (
      RX_POLARITY => '0',
      TX_POLARITY => '0',
      refclksel => '1')
    port map (
      sys_clk => sys_clk,
      refclk_out => refclk,
      event_clk_out => event_clk,
      
      -- Receiver side connections
      event_rxd => event_rxd,
      dbus_rxd => dbus_rxd,
      databuf_rxd => databuf_rxd,
      databuf_rx_k => databuf_rx_k,
      databuf_rx_ena => databuf_rx_ena,
      databuf_rx_mode => databuf_rx_mode,
      dc_mode => dc_mode,
      
      rx_link_ok => rx_link_ok,
      rx_violation => rx_violation,
      rx_clear_viol => rx_clear_viol,
      
      -- Transmitter side connections
      event_txd => event_txd,
      dbus_txd => dbus_txd,
      databuf_txd => databuf_txd,
      databuf_tx_k => databuf_tx_k,
      databuf_tx_ena => databuf_tx_ena,
      databuf_tx_mode => databuf_tx_mode,

      reset => tx_reset,

      delay_comp_update => delay_comp_update,
      delay_comp_value => delay_comp_value,
      delay_comp_target => delay_comp_target,
      delay_comp_locked_out => delay_comp_locked,
      
      MGTREFCLK0_P => gnd,
      MGTREFCLK0_N => gnd,
      MGTREFCLK1_P => MGTREFCLK1_P,
      MGTREFCLK1_N => MGTREFCLK1_N,
      
      
      MGTRX2_N => MGTRX2_N,
      MGTRX2_P => MGTRX2_p,

      MGTTX2_N => MGTTX2_N,
      MGTTX2_P => MGTTX2_P);

  i_databuf_dc : databuf_rx_dc
    port map (
      data_out => databuf_dc_data_out,
      size_data_out => databuf_dc_size_out,
      addr_in(10 downto 2) => databuf_dc_addr,
      clk => sys_clk,

      databuf_data => databuf_rxd,
      databuf_k => databuf_rx_k,
      databuf_ena => databuf_rx_ena,
      event_clk => event_clk,

      delay_comp_update => delay_comp_update,
      delay_comp_rx => delay_comp_value,
      delay_comp_status => delay_comp_rx_status,
      topology_addr => topology_addr,
      
      irq_out => databuf_irq_dc,

      sirq_ena => databuf_sirq_ena,
      rx_flag => databuf_rx_flag,
      cs_flag => databuf_cs_flag,
      ov_flag => databuf_ov_flag,
      clear_flag => databuf_clear_flag,

      reset => sys_reset);

  gnd <= '0';
  vcc <= '1';
  
  databuf_rx_mode <= '1';
  databuf_tx_mode <= '1';
  dc_mode <= '1';

  delay_comp_target <= X"02100000";

  dbus_txd <= X"00";
  databuf_txd <= X"00";
  databuf_tx_k <= '0';

  -- Process to send out event 0x01 periodically
  process (refclk)
    variable count : std_logic_vector(31 downto 0) := X"FFFFFFFF";
  begin
    if rising_edge(refclk) then
      event_txd <= X"00";
      if count(26) = '0' then
	event_txd <= X"01";
	count := X"FFFFFFFF";
      end if;
      count := count - 1;
    end if;
  end process;
  
  
  process (sys_clk)
    variable count : std_logic_vector(31 downto 0) := X"FFFFFFFF";
  begin
    if rising_edge(sys_clk) then
      rx_clear_viol <= PL_PB1;
      tx_reset <= PL_PB2;
      sys_reset <= PL_PB3;
      PL_LED1 <= rx_violation;
      PL_LED2 <= rx_link_ok;
--      PL_LED3 <= event_rxd(0);
      PL_LED4 <= count(25);
      count := count - 1;
    end if;
  end process;

  process (event_clk)
  begin
    if rising_edge(event_clk) then
      TRIG0(7 downto 0) <= event_rxd;
      TRIG0(15 downto 8) <= dbus_rxd;
      TRIG0(23 downto 16) <= databuf_rxd;
      TRIG0(24) <= databuf_rx_k;
      TRIG0(25) <= databuf_rx_ena;
      TRIG0(26) <= databuf_rx_mode;
      TRIG0(27) <= rx_link_ok;
      TRIG0(28) <= rx_violation;
      TRIG0(29) <= rx_clear_viol;
      TRIG0(30) <= delay_comp_locked;
      TRIG0(31) <= delay_comp_update;
      TRIG0(63 downto 32) <= delay_comp_value;
      TRIG0(95 downto 64) <= delay_comp_target;
      TRIG0(127 downto 96) <= dc_status;
      TRIG0(159 downto 128) <= delay_comp_rx_status;
      TRIG0(191 downto 160) <= topology_addr;
      TRIG0(255 downto 192) <= (others => '0');
    end if;
  end process;

  process (event_clk, event_rxd)
    variable pulse_cnt : std_logic_vector(19 downto 0) := X"00000";
  begin
    if rising_edge(event_clk) then
      PL_LED3 <= pulse_cnt(pulse_cnt'high);
      BANK13_LVDS_8_P <= pulse_cnt(pulse_cnt'high);
      BANK13_LVDS_8_N <= not pulse_cnt(pulse_cnt'high);
      if pulse_cnt(pulse_cnt'high) = '1' then
	pulse_cnt := pulse_cnt - 1;
      end if;
      if event_rxd = X"01" then
	pulse_cnt := X"FFFFF";
      end if;
      if rx_link_ok = '0' then
	pulse_cnt := X"0000F";
      end if;
    end if;
  end process;
    
  
end structure;
