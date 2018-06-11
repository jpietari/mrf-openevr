library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library UNISIM;
use UNISIM.Vcomponents.ALL;

entity evr_dc is
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

    reset           : in  std_logic; -- Transceiver reset

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
end evr_dc;

architecture structure of evr_dc is

  component transceiver_dc_k7 is
    generic
      (
        RX_DFE_KL_CFG2_IN            : bit_vector :=  X"3010D90C";
        PMA_RSV_IN                   : bit_vector :=  x"00018480";
        PCS_RSVD_ATTR_IN             : bit_vector :=  X"000000000002";
        RX_POLARITY                  : std_logic := '0';
        TX_POLARITY                  : std_logic := '0';
        REFCLKSEL                    : std_logic := '0' -- 0 - REFCLK0, 1 - REFCLK1
        );
    port (
      sys_clk         : in std_logic;
      REFCLK0P        : in std_logic;
      REFCLK0N        : in std_logic;
      REFCLK1P        : in std_logic;
      REFCLK1N        : in std_logic;
      REFCLK_OUT      : out std_logic;
      recclk_out      : out std_logic;
      event_clk       : in std_logic;
      
      -- Receiver side connections
      event_rxd       : out std_logic_vector(7 downto 0);
      dbus_rxd        : out std_logic_vector(7 downto 0);
      databuf_rxd     : out std_logic_vector(7 downto 0);
      databuf_rx_k    : out std_logic;
      databuf_rx_ena  : out std_logic;
      databuf_rx_mode : in std_logic;
      dc_mode         : in std_logic;
      
      rx_link_ok      : out   std_logic;
      rx_violation    : out   std_logic;
      rx_clear_viol   : in    std_logic;
      rx_beacon       : out   std_logic;
      tx_beacon       : out   std_logic;
      rx_int_beacon   : out   std_logic;
      
      delay_inc       : in    std_logic;
      delay_dec       : in    std_logic;
      
      reset           : in    std_logic;
      
      -- Transmitter side connections
      event_txd       : in  std_logic_vector(7 downto 0);
      dbus_txd        : in  std_logic_vector(7 downto 0);
      databuf_txd     : in  std_logic_vector(7 downto 0);
      databuf_tx_k    : in  std_logic;
      databuf_tx_ena  : out std_logic;
      databuf_tx_mode : in  std_logic;
      
      RXN             : in    std_logic;
      RXP             : in    std_logic;
      
      TXN             : out   std_logic;
      TXP             : out   std_logic
      );
  end component;

  component delay_measure is
    generic (
      MAX_DELAY_BITS         : integer := 16;
      FRAC_DELAY_BITS        : integer := 16;
      CYCLE_CNT_BITS_0       : integer := 10;
      CYCLE_CNT_BITS_1       : integer := 16;
      CYCLE_CNT_BITS_2       : integer := 20);
    port (
      clk              : in std_logic;
      beacon_0         : in std_logic;
      beacon_1         : in std_logic;

      fast_adjust      : in std_logic;
      slow_adjust      : in std_logic;
      reset            : in std_logic;
    
      delay_out        : out std_logic_vector(31 downto 0);
      slow_delay_out   : out std_logic_vector(31 downto 0);
      delay_update_out : out std_logic;
      init_done        : out std_logic);
  end component;

  component delay_adjust is
    port (
      clk        : in std_logic;
      
      psclk      : in  std_logic;
      psen       : out std_logic;
      psincdec   : out std_logic;
      psdone     : in  std_logic;
      
      link_ok    : in  std_logic;
      delay_inc  : out std_logic;
      delay_dec  : out std_logic;
      int_clk_mode : in std_logic;
      
      adjust_locked     : out std_logic;

      feedback   : in  std_logic_vector(1 downto 0);
      pwm_param  : in  std_logic_vector(1 downto 0);
      disable           : in  std_logic;
      dc_mode           : in  std_logic;
      
      override_mode     : in  std_logic;
      override_update   : in  std_logic;
      override_adjust   : in  std_logic_vector(31 downto 0);
      dc_status         : out std_logic_vector(31 downto 0);
    
      delay_comp_update : in std_logic;
      delay_comp_value  : in std_logic_vector(31 downto 0);
      delay_comp_target : in std_logic_vector(31 downto 0);
      int_delay_value   : in std_logic_vector(31 downto 0);
      int_delay_update  : in std_logic;
      int_delay_init    : in std_logic);
  end component;

  signal gnd     : std_logic;
  signal vcc     : std_logic;
  
  signal refclk  : std_logic;
  signal test_mode       : std_logic;

  signal CLKCLN_OUT         : std_logic;

  signal event_clk : std_logic;
  signal cdr_clk : std_logic;
  signal dcm_clk : std_logic;
  signal event_link_ok : std_logic;

  signal int_clk_mode       : std_logic_vector(1 downto 0);
  signal run_on_refclk      : std_logic;

  signal up_event_clk       : std_logic;
  signal up_event_rxd       : std_logic_vector(7 downto 0);
  signal up_dbus_rxd        : std_logic_vector(7 downto 0);
  signal up_databuf_rxd     : std_logic_vector(7 downto 0);
  signal up_databuf_rx_k    : std_logic;
  signal up_databuf_rx_ena  : std_logic;
  signal up_databuf_rx_mode : std_logic;
    
  signal up_rx_link_ok      : std_logic;
  signal up_rx_violation    : std_logic;
  signal up_rx_clear_viol   : std_logic;
  signal up_rx_beacon       : std_logic;
  signal up_tx_beacon       : std_logic;
  signal up_rx_int_beacon   : std_logic;
  signal up_delay_inc       : std_logic;
  signal up_delay_dec       : std_logic;
  signal up_event_txd       : std_logic_vector(7 downto 0);
  signal up_dbus_txd        : std_logic_vector(7 downto 0);
  signal up_databuf_txd     : std_logic_vector(7 downto 0);
  signal up_databuf_tx_k    : std_logic;
  signal up_databuf_tx_ena  : std_logic;
  signal up_databuf_tx_mode : std_logic;

  signal delay_comp_locked  : std_logic;

  signal da_feedback        : std_logic_vector(1 downto 0);
  signal da_pwm_param       : std_logic_vector(1 downto 0);
  signal da_override_mode   : std_logic;
  signal da_override_update : std_logic;
  signal da_override_adjust : std_logic_vector(31 downto 0);

  signal mmcm_clk0      : std_logic;
  signal mmcm_psdone    : std_logic;
  signal mmcm_clkfb     : std_logic;
  signal mmcm_reset     : std_logic;
  signal mmcm_psclk     : std_logic;
  signal mmcm_psen      : std_logic;
  signal mmcm_psincdec  : std_logic;
  signal mmcm_clkinsel  : std_logic;
  
  signal psinc          : std_logic;
  signal psdec          : std_logic;
  
  signal int_delay_value      : std_logic_vector(31 downto 0);
  signal int_slow_delay_value : std_logic_vector(31 downto 0);
  signal int_delay_update     : std_logic;
  signal int_delay_init       : std_logic;
  signal int_delay_reset      : std_logic;

  signal dc_fast_adjust       : std_logic;
  signal dc_slow_adjust       : std_logic;

  signal dc_status        : std_logic_vector(31 downto 0);

begin

  i_upstream : transceiver_dc_k7
    generic map (
      RX_POLARITY => '0',
      TX_POLARITY => '0',
      refclksel => '1')
    port map (
      sys_clk => sys_clk,
      REFCLK0P => gnd,
      REFCLK0N => gnd,
      REFCLK1P => MGTREFCLK1_P,
      REFCLK1N => MGTREFCLK1_N,
      REFCLK_OUT => refclk,
      recclk_out => up_event_clk,
      event_clk => event_clk,
      
      -- Receiver side connections
      event_rxd => up_event_rxd,
      dbus_rxd => up_dbus_rxd,
      databuf_rxd => up_databuf_rxd,
      databuf_rx_k => up_databuf_rx_k,
      databuf_rx_ena => up_databuf_rx_ena,
      databuf_rx_mode => up_databuf_rx_mode,
      dc_mode => dc_mode,
      
      rx_link_ok => up_rx_link_ok,
      rx_violation => up_rx_violation,
      rx_clear_viol => up_rx_clear_viol,
      rx_beacon => up_rx_beacon,
      tx_beacon => up_tx_beacon,
      rx_int_beacon => up_rx_int_beacon,

      delay_inc => up_delay_inc,
      delay_dec => up_delay_dec,
      
      reset => reset,

      -- Transmitter side connections
      event_txd => event_txd,
      dbus_txd => dbus_txd,
      databuf_txd => databuf_txd,
      databuf_tx_k => databuf_tx_k,
      databuf_tx_ena => databuf_tx_ena,
      databuf_tx_mode => databuf_tx_mode,

      RXN => MGTRX2_N,
      RXP => MGTRX2_p,

      TXN => MGTTX2_N,
      TXP => MGTTX2_P);

  int_dly : delay_measure
    port map (
      clk => refclk,
      beacon_0 => up_rx_beacon,
      beacon_1 => up_rx_int_beacon,
      fast_adjust => dc_fast_adjust,
      slow_adjust => dc_slow_adjust,
      reset => int_delay_reset,
      delay_out => int_delay_value,
      slow_delay_out => int_slow_delay_value,
      delay_update_out => int_delay_update,
      init_done => int_delay_init);  

  int_dly_adj : delay_adjust
    port map (
      clk        => sys_clk,
      psclk      => refclk, -- mmcm_psclk,
      psen       => mmcm_psen,
      psincdec   => mmcm_psincdec,
      psdone     => mmcm_psdone,
      
      link_ok    => up_rx_link_ok,
      delay_inc  => up_delay_inc,
      delay_dec  => up_delay_dec,
      int_clk_mode => run_on_refclk,

      adjust_locked => delay_comp_locked,
      
      feedback   => da_feedback, -- test_out(2 downto 1),
      pwm_param  => da_pwm_param, -- test_out(4 downto 3),
      disable    => test_mode,
      dc_mode    => dc_mode,
      
      override_mode => da_override_mode,
      override_update => da_override_update,
      override_adjust => da_override_adjust,
      dc_status => dc_status,
      
      delay_comp_update => delay_comp_update,
      delay_comp_value  => delay_comp_value,
      delay_comp_target => delay_comp_target,
      int_delay_value   => int_delay_value,
      int_delay_update  => int_delay_update,
      int_delay_init    => int_delay_init);

  mmc_i : MMCME2_ADV
    generic map (
      BANDWIDTH => "OPTIMIZED",
      CLKFBOUT_MULT_F => 7.0,
      CLKFBOUT_PHASE => 0.0,
      CLKIN1_PERIOD => 7.0,
      CLKIN2_PERIOD => 0.0,
      CLKOUT0_DIVIDE_F => 7.000,
      CLKOUT1_DIVIDE => 1,
      CLKOUT2_DIVIDE => 1,
      CLKOUT3_DIVIDE => 1,
      CLKOUT4_DIVIDE => 1,
      CLKOUT5_DIVIDE => 1,
      CLKOUT6_DIVIDE => 1,
      CLKOUT0_DUTY_CYCLE => 0.5,
      CLKOUT1_DUTY_CYCLE => 0.5,
      CLKOUT2_DUTY_CYCLE => 0.5,
      CLKOUT3_DUTY_CYCLE => 0.5,
      CLKOUT4_DUTY_CYCLE => 0.5,
      CLKOUT5_DUTY_CYCLE => 0.5,
      CLKOUT6_DUTY_CYCLE => 0.5,
      CLKOUT0_PHASE => 0.0,
      CLKOUT1_PHASE => 0.0,
      CLKOUT2_PHASE => 0.0,
      CLKOUT3_PHASE => 0.0,
      CLKOUT4_PHASE => 0.0,
      CLKOUT5_PHASE => 0.0,
      CLKOUT6_PHASE => 0.0,
      CLKOUT4_CASCADE => FALSE,
      COMPENSATION => "ZHOLD",
      DIVCLK_DIVIDE => 1,
      REF_JITTER1 => 0.01,
      REF_JITTER2 => 0.01,
      STARTUP_WAIT => FALSE,
      SS_MODE => "CENTER_HIGH",
      SS_MOD_PERIOD => 10000,
      CLKFBOUT_USE_FINE_PS => FALSE,
      CLKOUT0_USE_FINE_PS => TRUE,
      CLKOUT1_USE_FINE_PS => FALSE,
      CLKOUT2_USE_FINE_PS => FALSE,
      CLKOUT3_USE_FINE_PS => FALSE,
      CLKOUT4_USE_FINE_PS => FALSE,
      CLKOUT5_USE_FINE_PS => FALSE,
      CLKOUT6_USE_FINE_PS => FALSE)
    port map (
      CLKOUT0 => mmcm_clk0,
      CLKOUT0B => open,
      CLKOUT1 => open,
      CLKOUT1B => open,
      CLKOUT2 => open,
      CLKOUT2B => open,
      CLKOUT3 => open,
      CLKOUT3B => open,
      CLKOUT4 => open,
      CLKOUT5 => open,
      CLKOUT6 => open,
      DO => open,
      DRDY => open,
      PSDONE => mmcm_psdone,
      CLKFBOUT => mmcm_clkfb,
      CLKFBOUTB => open,
      CLKFBSTOPPED => open,
      CLKINSTOPPED => open,
      LOCKED => open,
      CLKIN1 => up_event_clk,
      CLKIN2 => refclk,
      CLKINSEL => mmcm_clkinsel,
      PWRDWN => gnd,
      RST => mmcm_reset,
      DADDR => "0000000",
      DCLK => gnd,
      DEN => gnd,
      DI => X"0000",
      DWE => gnd,
      PSCLK => mmcm_psclk,
      PSEN => mmcm_psen,
      PSINCDEC => mmcm_psincdec,
      CLKFBIN => mmcm_clkfb);

  i_bufg_synclk : BUFG
    port map (
      I => mmcm_clk0,
      O => event_clk);

  refclk_out <= refclk;
  event_clk_out <= event_clk;
  event_rxd <= up_event_rxd;
  dbus_rxd <= up_dbus_rxd;
  databuf_rxd <= up_databuf_rxd;
  databuf_rx_k <= up_databuf_rx_k;
  databuf_rx_ena <= up_databuf_rx_ena;
  rx_link_ok <= up_rx_link_ok;
  rx_violation <= up_rx_violation;
  up_rx_clear_viol <= rx_clear_viol;
  databuf_tx_ena <= up_databuf_tx_ena;
  
  gnd <= '0';
  vcc <= '1';
  
  da_feedback <= "01";
  da_pwm_param <= "11";
  da_override_mode <= '0';
  
  up_databuf_rx_mode <= databuf_rx_mode;
  up_databuf_tx_mode <= databuf_tx_mode;

  dc_fast_adjust <= not delay_comp_locked;
  dc_slow_adjust <= '0'; -- test_out(0);
  delay_comp_locked_out <= delay_comp_locked;
  
  run_on_refclk <= '0';
  test_mode <= '0';
  int_delay_reset <= not up_rx_link_ok;

  mmcm_clkinsel <= not run_on_refclk; -- high: select CLKIN1
  mmcm_reset <= not up_rx_link_ok;
  
  process (sys_clk, mmcm_psen, mmcm_psincdec)
  begin
    if rising_edge(sys_clk) then
      psinc <= '0';
      psdec <= '0';
      if mmcm_psen = '1' then
        if mmcm_psincdec = '1' then
          psinc <= '1';
        else
          psdec <= '1';
        end if;
      end if;
    end if;
  end process;

end structure;
