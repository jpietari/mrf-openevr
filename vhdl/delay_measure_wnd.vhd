---------------------------------------------------------------------------
--
--  File        : delay_measure.vhd
--
--  Title       : Delay measurement between two signals on unrelated
--                clock but almost same frequency
--                Windowed acquisition with averaging over defined time
--
--  Author      : Jukka Pietarinen
--                Micro-Research Finland Oy
--                <jukka.pietarinen@mrf.fi>
--
--  		
--
---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity delay_measure is
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
    init_done        : out std_logic;

    debug_out        : out std_logic_vector(31 downto 0)
    );
end delay_measure;

architecture rtl of delay_measure is

  signal delay_cnt      : std_logic_vector(MAX_DELAY_BITS-1 downto 0);
  signal delay_update   : std_logic;
  signal gnd_vec        : std_logic_vector(MAX_DELAY_BITS+FRAC_DELAY_BITS-1 downto 0);
  signal vcc_vec        : std_logic_vector(MAX_DELAY_BITS+FRAC_DELAY_BITS-1 downto 0);

  signal reset_count    : std_logic;
  signal reset_count_2  : std_logic;
  signal valid          : std_logic_vector(2 downto 0);
  signal average_0      : std_logic_vector(MAX_DELAY_BITS+CYCLE_CNT_BITS_0-1 downto 0);
  signal average_1      : std_logic_vector(MAX_DELAY_BITS+CYCLE_CNT_BITS_1-1 downto 0);
  signal average_2      : std_logic_vector(MAX_DELAY_BITS+CYCLE_CNT_BITS_2-1 downto 0);
  
  component average is
    generic (
      NAT_BITS  : integer := 16;
      FRAC_BITS : integer := 16);
    port (
      clk             : in std_logic;
      value_in        : in std_logic_vector(NAT_BITS-1 downto 0);
      value_valid     : in std_logic;
      reset           : in std_logic;
      average_out     : out std_logic_vector(NAT_BITS+FRAC_BITS-1 downto 0);
      average_valid   : out std_logic
      );
  end component;
  
begin

  debug_out(0) <= reset_count;
  debug_out(1) <= reset_count_2;
  debug_out(4 downto 2) <= valid;
  debug_out(5) <= delay_update;
  debug_out(MAX_DELAY_BITS-1+6 downto 6) <= delay_cnt;
  debug_out(28 downto MAX_DELAY_BITS+6) <= (others => '0');
  
  i_ave_0 : average
    generic map (
      NAT_BITS => MAX_DELAY_BITS,
      FRAC_BITS => CYCLE_CNT_BITS_0)
    port map (
      clk => clk,
      value_in => delay_cnt,
      value_valid => delay_update,
      reset => reset_count,
      average_out => average_0,
      average_valid => valid(0));

  i_ave_1 : average
    generic map (
      NAT_BITS => MAX_DELAY_BITS,
      FRAC_BITS => CYCLE_CNT_BITS_1)
    port map (
      clk => clk,
      value_in => delay_cnt,
      value_valid => delay_update,
      reset => reset_count,
      average_out => average_1,
      average_valid => valid(1));
  
  i_ave_2 : average
    generic map (
      NAT_BITS => MAX_DELAY_BITS,
      FRAC_BITS => CYCLE_CNT_BITS_2)
    port map (
      clk => clk,
      value_in => delay_cnt,
      value_valid => delay_update,
      reset => reset_count_2,
      average_out => average_2,
      average_valid => valid(2));
  
--  o_delay_cnt <= delay_cnt;
--  o_delay_update <= delay_update;

  gnd_vec <= (others => '0');
  vcc_vec <= (others => '1');
  
  process (clk, beacon_0, beacon_1, reset)
    variable counting      : std_logic := '0';
    variable prev_cnt      : std_logic_vector(MAX_DELAY_BITS-1 downto 0);
    variable cnt           : std_logic_vector(MAX_DELAY_BITS-1 downto 0);
    variable diff_cnt      : std_logic_vector(MAX_DELAY_BITS-1 downto 0);
    variable sync_beacon_0 : std_logic_vector(3 downto 0) := "0000";
    variable sync_beacon_1 : std_logic_vector(3 downto 0) := "0000";
    variable cnt_valid     : std_logic;
  begin
    if rising_edge(clk) then
      reset_count <= '0';
      reset_count_2 <= '0';
      delay_update <= '0';
      if counting = '1' then
        cnt := cnt + 1;
      end if;
      if sync_beacon_0(1 downto 0) = "10" then
        cnt := (others => '0');
        counting := '1';
        cnt_valid := '1';
      end if;
      if sync_beacon_1(1 downto 0) = "10" then
        if counting = '1' then
          delay_cnt <= cnt;
          counting := '0';
          diff_cnt := prev_cnt - cnt;
          if diff_cnt(MAX_DELAY_BITS-1 downto 2) /= gnd_vec(MAX_DELAY_BITS-1 downto 2) and
            diff_cnt(MAX_DELAY_BITS-1 downto 2) /= vcc_vec(MAX_DELAY_BITS-1 downto 2) then
            cnt_valid := '0';
            reset_count <= '1';
            reset_count_2 <= '1';
          else
            delay_update <= '1';
          end if;
          prev_cnt := cnt;
        end if;
      end if;
      
      if reset = '1' or cnt_valid = '0' then
        counting := '0';
      end if;

      if fast_adjust = '1' then
        reset_count_2 <= '1';
      end if;

      if reset = '1' then
        reset_count <= '1';
        reset_count_2 <= '1';
      end if;

      sync_beacon_0 := beacon_0 & sync_beacon_0(3 downto 1);
      sync_beacon_1 := beacon_1 & sync_beacon_1(3 downto 1);
    end if;
  end process;

  process (clk, reset, fast_adjust, average_0, average_1, average_2, valid)
    variable upd_cnt   : std_logic_vector(4 downto 0);
    variable dly_diff  : std_logic_vector(22 downto 0);
    variable val_valid : std_logic_vector(2 downto 0);
  begin
    debug_out(31 downto 29) <= val_valid; 
    if rising_edge(clk) then
      delay_update_out <= upd_cnt(upd_cnt'high);
      if upd_cnt(upd_cnt'high) = '1' then
        upd_cnt := upd_cnt - 1;
      end if;
      dly_diff := average_2(average_2'high downto average_2'high-22) -
        average_1(average_1'high downto average_1'high-22);
      if valid(0) = '1' then
        val_valid(0) := '1';
        if val_valid(2 downto 1) = "00" then
          slow_delay_out <= (others => '0');
          slow_delay_out(delay_out'high downto
                    delay_out'high-MAX_DELAY_BITS-CYCLE_CNT_BITS_0+1)
            <= average_0;
        end if;
      end if;
      if valid(1) = '1' then
        val_valid(1) := '1';
        if val_valid(2) = '0' then
          slow_delay_out <= average_1(average_1'high
                                      downto
                                      average_1'high
                                      -MAX_DELAY_BITS
                                      -FRAC_DELAY_BITS+1);
        end if;
      end if;
      if valid(2) = '1' then
        val_valid(2) := '1';
        slow_delay_out <= average_2(average_2'high
                                    downto
                                    average_2'high
                                    -MAX_DELAY_BITS
                                    -FRAC_DELAY_BITS+1);
      end if;
      if fast_adjust = '1' then
        if valid(0) = '1' then
          delay_out <= (others => '0');
          delay_out(delay_out'high downto
                    delay_out'high-MAX_DELAY_BITS-CYCLE_CNT_BITS_0+1)
            <= average_0;
          upd_cnt := (others => '1');
        end if;
      else
        if slow_adjust = '1' then
          if valid(2) = '1' then
            delay_out <= average_2(average_2'high
                                   downto
                                   average_2'high
                                   -MAX_DELAY_BITS
                                   -FRAC_DELAY_BITS+1);
            upd_cnt := (others => '1');
          end if;
        else
          if valid(1) = '1' then
            delay_out <= average_1(average_1'high
                                 downto
                                 average_1'high
                                 -MAX_DELAY_BITS
                                 -FRAC_DELAY_BITS+1);
            upd_cnt := (others => '1');
          end if;
        end if;
      end if;
      if reset = '1' then
        val_valid := (others => '0');
      end if;
    end if;
  end process;

  process (clk, reset, valid)
  begin
    if rising_edge(clk) then
      if valid(0) = '1' then
        init_done <= '1';
      end if;
      if reset = '1' then
        init_done <= '0';
      end if;
    end if;
  end process;
  
end rtl;
  
