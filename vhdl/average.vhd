---------------------------------------------------------------------------
--
--  File        : average.vhd
--
--  Title       : Average a value over a period of cycles
--
--  Author      : Jukka Pietarinen
--                Micro-Research Finland Oy
--                <jukka.pietarinen@mrf.fi>
--
---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity average is
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
end average;

architecture rtl of average is

begin
  
  process (clk, value_in, value_valid, reset)
    variable sum        : std_logic_vector(NAT_BITS+FRAC_BITS-1 downto 0);
    variable change     : std_logic_vector(NAT_BITS+FRAC_BITS-1 downto 0);
    variable update_cnt : std_logic_vector(FRAC_BITS downto 0);
  begin
    if rising_edge(clk) then
      average_valid <= '0';
      if update_cnt(update_cnt'high) = '1' then
        if value_valid = '1' then
          change := (others => '0');
          change(NAT_BITS+FRAC_BITS-FRAC_BITS-1
                       downto FRAC_BITS-FRAC_BITS) := value_in;
          sum := sum + change;
          update_cnt := update_cnt - 1;
        end if;
      else
        average_valid <= '1';
        average_out <= sum;
        sum := (others => '0');
        update_cnt := (others => '1');
      end if;
      if reset = '1' then
        sum := (others => '0');
        update_cnt := (others => '1');
      end if;
    end if;
  end process;

end rtl;
