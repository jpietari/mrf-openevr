---------------------------------------------------------------------------
--
--  File        : delay_adjust.vhd
--
--  Title       : EVR FIFO/DCM delay adjust
--
--  Author      : Jukka Pietarinen
--                Micro-Research Finland Oy
--                <jukka.pietarinen@mrf.fi>
--
--
---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
--
-- Delay adjust steps
-- 0 - initial state, arbitrary delay, wait for delay_value_valid for path and
-- FIFO
-- 1 - adjust FIFO by error cycles and DCM phase by error fraction, when done
-- move to state 2
-- 2 - wait for FIFO delay_value_valid, minimum of Tadj cycles, move to state 3
-- 3 - adjust DCM phase by error fraction, when done move to state 2
-- General: if delay_value_valid for path is not valid, move to state 0 (stop
-- adjustment until value valid)

-- Changes:
-- capability to change DCM phase by cycle fraction
-- We have to be aware of event_clk/VCO relationship as one DCM step is 1/56
-- VCO cycle
-- modulate DCM with PWM: adjustable PWM frequency, duty cycle precision
-- PSEN to PSDONE 12 cycles -> select minimum period 16 PSCLK cycles
-- change PSCLK to event_clk
-- 1024 period will give 7 us or 140 kHz PWM frequency and in theory a
-- resolution of 7 ns / (7*56*64) = 0.28 ps steps

entity delay_adjust is
  port (
    clk        : in std_logic;

    psclk      : in  std_logic;
    psen       : out std_logic;
    psincdec   : out std_logic;
    psdone     : in  std_logic;

    link_ok      : in  std_logic;
    delay_inc    : out std_logic;
    delay_dec    : out std_logic;
    int_clk_mode : in std_logic;
    
    adjust_locked     : out std_logic;

    feedback   : in  std_logic_vector(1 downto 0);
    pwm_param  : in  std_logic_vector(1 downto 0);
    disable    : in  std_logic;
    dc_mode    : in  std_logic;
    
    override_mode     : in  std_logic;
    override_update   : in  std_logic;
    override_adjust   : in  std_logic_vector(31 downto 0);
    dc_status         : out std_logic_vector(31 downto 0);
    
    delay_comp_update : in std_logic;
    delay_comp_value  : in std_logic_vector(31 downto 0);
    delay_comp_target : in std_logic_vector(31 downto 0);
    int_delay_value   : in std_logic_vector(31 downto 0);
    int_delay_update  : in std_logic;
    int_delay_init    : in std_logic    
    );
end entity delay_adjust;

architecture struct of delay_adjust is
  
  signal phase_error     : std_logic_vector(31 downto 0);
  signal delay_valid     : std_logic;
  signal delay_too_short : std_logic;
  signal delay_too_long  : std_logic;
  
  signal dcm_adjust      : std_logic;
  signal dcm_inc         : std_logic;
  signal dcm_fine_adjust : std_logic;
  signal dcm_reload_err  : std_logic;
  
  signal ce              : std_logic;

  signal state_i         : std_logic_vector(2 downto 0);
  signal cycle_error_i   : std_logic_vector(15 downto 0);
  signal cnt_i           : std_logic_vector(4 downto 0);
  signal long_delay_i    : std_logic_vector(31 downto 0);
  signal fe_inc_i        : std_logic_vector(17 downto 0);
  signal fe_dec_i        : std_logic_vector(17 downto 0);
  signal dcm_adjust_frac : std_logic_vector(17 downto 0);
  signal adjust_locked_i : std_logic;

  signal dcm_update      : std_logic := '0';
  signal dcm_step_change : std_logic_vector(2 downto 0) := "000";
  signal dcm_phase_change : std_logic_vector(5 downto 0) := "000000";

  signal s_dcm_step_phase : std_logic_vector(3 downto 0);
  signal s_dcm_phase   : std_logic_vector(5 downto 0);
  signal s_pwm_cnt     : std_logic_vector(10 downto 0);
  signal s_pulse_cnt   : std_logic_vector(10 downto 0);
  signal s_zero_phase  : std_logic;
  signal s_pwm_done    : std_logic;

  signal err_phase_i   : std_logic_vector(11 downto 0);
  signal dcm_phase_int : std_logic_vector(11 downto 0);
  signal dcm_phase_0_i : std_logic_vector(11 downto 0);
  signal dcm_phase_i_i : std_logic_vector(11 downto 0);
  signal dcm_phase_d_i : std_logic_vector(11 downto 0);
  signal dcm_cycle_i   : std_logic_vector(11 downto 0);
  signal pwm_cnt_i     : std_logic_vector(10 downto 0);
  signal pulse_cnt_i   : std_logic_vector(10 downto 0);
  signal pwm_cnt_1_i   : std_logic;
  signal pwm_pol_i     : std_logic;
  signal new_pwm_pol_i : std_logic;

  signal swallow_inc_i : std_logic;
  signal swallow_dec_i : std_logic;
  
  signal TRIG0 : std_logic_vector(255 downto 0);

  COMPONENT ila_0
    PORT (
      clk : IN STD_LOGIC;
      probe0 : IN STD_LOGIC_VECTOR(255 DOWNTO 0)
      );
  END COMPONENT;

begin

--  i_ila : ila_0
--    port map (
--      CLK => clk,
--      probe0 => TRIG0);

  dc_status(31 downto 4) <= (others => '0');
  dc_status(3) <= delay_too_long;
  dc_status(2) <= delay_too_short;
  dc_status(1) <= delay_valid;
  dc_status(0) <= adjust_locked_i;
  
  process (clk, delay_comp_update, delay_comp_value, delay_comp_target,
           int_delay_value, int_delay_update, int_delay_init, dc_mode)
    variable sync_dc_value  : std_logic_vector(31 downto 0) := X"00000000";
    variable sync_id_value  : std_logic_vector(31 downto 0) := X"00000000";
    variable sync_dc_update : std_logic_vector(1 downto 0) := "00";
    variable sync_id_update : std_logic_vector(1 downto 0) := "00";
    variable sync_init      : std_logic_vector(1 downto 0) := "00";
    variable sync_dc_id     : std_logic_vector(31 downto 0) := X"00000000";
    variable delay_short    : std_logic_vector(31 downto 0) := X"00000000";
    variable delay_long     : std_logic_vector(31 downto 0) := X"00000000";
  begin
    if rising_edge(clk) then
      delay_valid <= sync_id_update(sync_id_update'high);
        phase_error <= delay_comp_target - sync_dc_id;
        if sync_init(sync_init'high) = '0' then
          phase_error <= (others => '0');
        end if;
        if sync_dc_update(sync_dc_update'high) = '1' then
          sync_dc_value := delay_comp_value;
        end if;
        if sync_id_update(sync_id_update'high) = '1' then
          sync_id_value := int_delay_value;
        end if;
      if override_mode = '1' or dc_mode = '0' then
        sync_dc_value := (others => '0');
      end if;
      sync_dc_id := sync_dc_value + sync_id_value;
      sync_dc_update := sync_dc_update(0) & delay_comp_update;
      sync_id_update := sync_id_update(0) & int_delay_update;
      sync_init := sync_init(0) & int_delay_init;

      
      delay_too_short <= '0';
      if delay_short(delay_short'high) = '1' then
        delay_too_short <= '1';
      end if;
      delay_too_long <= '0';
      if delay_long(delay_long'high) = '0' then
        delay_too_long <= '1';
      end if;
      delay_short := delay_comp_target - X"00060000" - sync_dc_value;
      delay_long := delay_comp_target - X"04000000" - sync_dc_value;
    end if;
  end process;

  cycle_adjust: process (clk, phase_error, delay_valid, disable, feedback) 
    variable state            : std_logic_vector(2 downto 0) := "000";
    variable cycle_error      : std_logic_vector(15 downto 0);
    variable cnt              : std_logic_vector(4 downto 0) := "00000";
    variable long_delay       : std_logic_vector(31 downto 0);
    variable fraction_error   : std_logic_vector(17 downto 0);
    variable fe_inc           : std_logic_vector(17 downto 0);
    variable fe_dec           : std_logic_vector(17 downto 0);
    variable fine_step        : std_logic_vector(17 downto 0) := "00" & X"0100";
    variable dcm_step         : std_logic_vector(17 downto 0) := "00" & X"00A7";
    variable updt_delay_sr    : std_logic_vector(2 downto 0) := "000";
    variable delay_value_updt : std_logic;
  begin
    state_i <= state;
    cycle_error_i <= cycle_error;
    cnt_i <= cnt;
    long_delay_i <= long_delay;
    fe_inc_i <= fe_inc;
    fe_dec_i <= fe_dec;
    dcm_adjust_frac <= fraction_error;
    adjust_locked <= adjust_locked_i;
    
    if rising_edge(clk) then
      delay_value_updt := '0';
      if updt_delay_sr(2 downto 1) = "01" then
        delay_value_updt := '1';
      end if;
      delay_inc <= '0';
      delay_dec <= '0';
      dcm_adjust <= '0';
      dcm_inc <= '0';
      ce <= cnt(cnt'high);
      dcm_reload_err <= '0';
      adjust_locked_i <= '0';
      dcm_update <= '0';
      if disable = '0' then
        if delay_value_updt = '1' then
          cycle_error := phase_error(31 downto 16);
          fraction_error := phase_error(31) & phase_error(31) & phase_error(15 downto 0);
          fe_inc := fraction_error + fine_step;
          fe_dec := fraction_error - fine_step;
          case feedback is
            when "00" =>
              dcm_step_change <= fraction_error(11 downto 9);
              dcm_phase_change <= fraction_error(8 downto 3);
            when "01" =>
              dcm_step_change <= fraction_error(10 downto 8);
              dcm_phase_change <= fraction_error(7 downto 2);
            when "10" =>
              dcm_step_change <= fraction_error(9 downto 7);
              dcm_phase_change <= fraction_error(6 downto 1);
            when others =>
              dcm_step_change <= fraction_error(8 downto 6);
              dcm_phase_change <= fraction_error(5 downto 0);
          end case;
          if fraction_error(fraction_error'high) = '0' and
            fe_inc(fe_inc'high) = '0' and fe_dec(fe_dec'high) = '0' then
            dcm_step_change <= "010";
            dcm_phase_change <= "000000";
          elsif fraction_error(fraction_error'high) = '1' and
            fe_inc(fe_inc'high) = '1' and fe_dec(fe_dec'high) = '1' then
            dcm_step_change <= "110";
            dcm_phase_change <= "000000";
          end if;          
          dcm_update <= '1';
        end if;
        
        case state is
          when "000" =>
            if delay_value_updt = '1' then
              state := "001";
            end if;
          when "001" =>
            if cnt(cnt'high) = '1' then
              if fe_inc(fe_inc'high) = '0' and fe_dec(fe_dec'high) = '1' then
                state := "011";
              else
                dcm_fine_adjust <= '0';
              end if;
              if cycle_error(cycle_error'high) = '0' then
                if cycle_error /= X"0000" then
                  delay_inc <= '1';
                  cycle_error := cycle_error - 1;
                end if;
              else
                if cycle_error /= X"FFFF" then
                  delay_dec <= '1';
                  cycle_error := cycle_error + 1;
                end if;
              end if;
            end if;
          when "011" =>
            dcm_reload_err <= '0';
            adjust_locked_i <= '1';
            if delay_value_updt = '1' then
              dcm_reload_err <= '1';
              dcm_fine_adjust <= '1';
              if fe_inc(fe_inc'high) = '1' or fe_dec(fe_dec'high) = '0' then
                state := "000";
              end if;
            end if;
          when others =>
        end case;
      end if;
      updt_delay_sr := updt_delay_sr(1 downto 0) & delay_valid;
      if int_clk_mode = '1' then
        delay_inc <= '0';
        delay_dec <= '0';
      end if;
      if link_ok = '0' then
        state := "000";
        dcm_fine_adjust <= '0';
        dcm_reload_err <= '0';
        adjust_locked_i <= '0';
      end if;
      if cnt(cnt'high) = '1' then
        cnt(cnt'high) := '0';
      end if;
      cnt := cnt + 1;
    end if;
  end process;
  
  dcm_control: process (psclk, dcm_step_change, dcm_phase_change, dcm_update, link_ok)
    variable dcm_step_phase : std_logic_vector(3 downto 0) := "0000";
    variable dcm_phase      : std_logic_vector(5 downto 0) := "000000";
    variable new_dcm_phase  : std_logic_vector(9 downto 0);
    variable pwm_cnt        : std_logic_vector(10 downto 0) := "00000000000";
    variable pulse_cnt      : std_logic_vector(10 downto 0) := "00000000000";
    variable zero_phase     : std_logic;
    variable pwm_done       : std_logic;
    variable psinc          : std_logic;
    variable psdec          : std_logic;
    variable dcm_updt_sr    : std_logic_vector(2 downto 0);
  begin
    if rising_edge(psclk) then
      psinc := '0';
      psdec := '0';
      if pulse_cnt(pulse_cnt'high) = '1' and pwm_done = '0' and zero_phase = '0' then
        pwm_done := '1';
        psdec := '1';
        if dcm_step_phase(dcm_step_phase'high) = '0' and
          dcm_step_phase(2 downto 0) /= "000" then
          psdec := '0';
          dcm_step_phase := dcm_step_phase - 1;
        end if;
      end if;
      if pwm_cnt(pwm_cnt'high) = '1' then
        pwm_cnt := (others => '1');
        pwm_cnt(pwm_cnt'high) := '0';
        case pwm_param is
          when "00" =>
            pulse_cnt := '0' & dcm_phase & "0000";
          when "01" =>
            pulse_cnt := '0' & dcm_phase(5 downto 1) & "00000";
          when "10" =>
            pulse_cnt := '0' & dcm_phase(5 downto 2) & "000000";
          when others =>
            pulse_cnt := '0' & dcm_phase(5 downto 3) & "0000000";
        end case;    
        zero_phase := '0';
        pwm_done := '0';
        if dcm_phase = "000000" then
          zero_phase := '1';
          if dcm_step_phase(dcm_step_phase'high) = '1' then
            psdec := '1';
            dcm_step_phase := dcm_step_phase + 1;
          elsif dcm_step_phase(2 downto 0) /= "000" then
            psinc := '1';
            dcm_step_phase := dcm_step_phase - 1;
          end if;
        else
          psinc := '1';
          if dcm_step_phase(dcm_step_phase'high) = '1' then
            psinc := '0';
            dcm_step_phase := dcm_step_phase + 1;
          end if;
        end if;
      end if;
      case pwm_param is
        when "00" => 
          pwm_cnt := pwm_cnt - 1;
          pulse_cnt := pulse_cnt - 1;
        when "01" =>
          pwm_cnt := pwm_cnt - 2;
          pulse_cnt := pulse_cnt - 2;
        when "10" =>
          pwm_cnt := pwm_cnt - 4;
          pulse_cnt := pulse_cnt - 4;
        when others =>
          pwm_cnt := pwm_cnt - 8;
          pulse_cnt := pulse_cnt - 8;
      end case;
      psen <= '0';
      psincdec <= '0';
      if int_clk_mode = '0' and psinc = '1' then
        psen <= '1';
        psincdec <= '1';
      end if;
      if int_clk_mode = '0' and psdec = '1' then
        psen <= '1';
        psincdec <= '0';
      end if;
      if dcm_updt_sr(2 downto 1) = "01" then
        if dcm_step_phase = "0000" then
          new_dcm_phase := dcm_step_phase & dcm_phase;
          new_dcm_phase := new_dcm_phase + (dcm_step_change(dcm_step_change'high)
                                            & dcm_step_change & dcm_phase_change);
          dcm_step_phase := new_dcm_phase(9 downto 6);
          dcm_phase := new_dcm_phase(5 downto 0);
        end if;
      end if;
      dcm_updt_sr := dcm_updt_sr(1 downto 0) & dcm_update;
      if link_ok = '0' then
        dcm_phase := (others => '0');
        pwm_cnt := (others => '1');
        pwm_cnt(pwm_cnt'high) := '0';
        pulse_cnt := (others => '0');
        zero_phase := '1';
        pwm_done := '0';
      end if;
    end if;

    s_dcm_step_phase <= dcm_step_phase;
    s_dcm_phase <= dcm_phase;
    s_pwm_cnt <= pwm_cnt;
    s_pulse_cnt <= pulse_cnt;
    s_zero_phase <= zero_phase;
    s_pwm_done <= pwm_done;

  end process;

  TRIG0(31 downto 0) <= phase_error;
  TRIG0(32) <= delay_valid;
  TRIG0(33) <= '0';
  TRIG0(34) <= '0';
  TRIG0(35) <= dcm_adjust;
  TRIG0(36) <= dcm_inc;
  TRIG0(37) <= dcm_fine_adjust;
  TRIG0(38) <= dcm_reload_err;
  TRIG0(39) <= ce;
  TRIG0(42 downto 40) <= state_i;
  TRIG0(61 downto 46) <= cycle_error_i;
  TRIG0(43) <= link_ok;
  TRIG0(44) <= disable;
  TRIG0(45) <= adjust_locked_i;
  TRIG0(127 downto 62) <= (others => '0');
  TRIG0(255 downto 162) <= (others => '0');

  TRIG0(131 downto 128) <= s_dcm_step_phase;
  TRIG0(137 downto 132) <= s_dcm_phase;
  TRIG0(148 downto 138) <= s_pwm_cnt;
  TRIG0(159 downto 149) <= s_pulse_cnt;
  TRIG0(160) <= s_zero_phase;
  TRIG0(161) <= s_pwm_done;

end struct;
