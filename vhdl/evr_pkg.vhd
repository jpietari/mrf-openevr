---------------------------------------------------------------------------
--
--  File        : evr_pkg.vhd
--
--  Title       : Event Receiver common definitions package
--
--  Author      : Jukka Pietarinen
--                Micro-Research Finland Oy
--                <jukka.pietarinen@mrf.fi>
--
---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

package evr_pkg is
  type integer_array is array (integer range <>) of integer;
  constant EVENT_RATE          : integer := 125000000;
  constant MGT_RX_PRESCALER    : integer := 1024;
  constant MGT_RX_TIMEOUT      : integer := 1024;
  constant MGT_RX_PWRDWN_TIME  : integer := 2;
  constant MGT_RX_LOCK_ACQ     : integer := 512;
  constant MGT_RX_K_COUNTER    : integer := 256;
  constant COUNT_10US          : integer := (EVENT_RATE / 100000);
  type cml_data_vector is array (integer range <>) of std_logic_vector(23 downto 0);
  type cml_we_vector is array (integer range<>) of std_logic_vector(2 downto 0);
  type cml_samples_vector is array (integer range <>) of std_logic_vector(10 downto 0);
  type trigger_vector is array (integer range<>) of std_logic_vector(31 downto 0);
  type count_vector is array (integer range<>) of std_logic_vector(31 downto 0);
  type we_vector is array (integer range<>) of std_logic_vector(3 downto 0);
  type data_vector is array (integer range<>) of std_logic_vector(31 downto 0);
  type short_vector is array (integer range<>) of std_logic_vector(15 downto 0);
  constant C_EVENT_CODE_BITS    : integer := 8;
  constant C_EVENT_HEARTBEAT    : std_logic_vector(7 downto 0) := X"7A";
  constant C_EVENT_BEACON       : std_logic_vector(7 downto 0) := X"7E";
  constant C_EVR_DBUS_BITS      : integer := 8;
  constant C_EVR_MAX_PULSE_GENS : integer := 32;
  constant C_EVR_PULSE_GATES    : integer := 4;
  constant C_EVR_MAP_RAMS       : integer := 2;
  -- C_EVR_MAP_RAM_CODE_ABITS defines the number of address bits one event
  -- code in the mapping ram occupies
  -- currently only 4 i.e. 2**4 = 16 bytes i.e. 128 bit is supported
  constant C_EVR_MAP_CODE_ABITS : integer := 4;
  type event_map_vector is array (integer range<>) of std_logic_vector(0 to 8*(2**C_EVR_MAP_CODE_ABITS)-1);
  -- C_SIGNAL_MAP_BITS defines the number of mapping bits in the
  -- front panel mapping registers, universal output mapping registers
  -- and transition board mapping registers
  constant C_SIGNAL_MAP_BITS   : integer := 6;
  -- C_SIGNAL_MAP_DBUS defines the starting index of DBUS bit 0
  constant C_SIGNAL_MAP_DBUS   : integer := 32;
  -- C_SIGNAL_MAP_PRESC defines the starting index of the prescaler outputs
  constant C_SIGNAL_MAP_PRESC  : integer := 40;
  -- C_SIGNAL_MAP_HIGH defines the index for state high output
  -- undefined indexes drive the output low
  constant C_SIGNAL_MAP_HIGH   : integer := 62;
  constant C_SIGNAL_MAP_Z      : integer := 61;
  constant C_SIGNAL_MAP_CLK    : integer := 60;
  constant C_SIGNAL_MAP_ICLK   : integer := 59;
  type signal_map_vector is array (integer range<>) of std_logic_vector(C_SIGNAL_MAP_BITS-1 downto 0);
  -- C_EVR_REG_CMPMIN defines the first address bit to compare 
  constant C_EVR_REG_CMP_LOW          : integer := 14;
  constant C_EVR_REG_STATUS           : std_logic_vector(0 to 31) := X"00000000";
  constant C_EVR_REG_CONTROL          : std_logic_vector(0 to 31) := X"00000004";
  constant C_EVR_REG_IRQFLAG          : std_logic_vector(0 to 31) := X"00000008";
  constant C_EVR_REG_IRQENABLE        : std_logic_vector(0 to 31) := X"0000000C";
  constant C_EVR_REG_PULSE_IRQ_MAP    : std_logic_vector(0 to 31) := X"00000010";
  constant C_EVR_REG_SW_EVENT         : std_logic_vector(0 to 31) := X"00000018";
  constant C_EVR_REG_MIRQENABLE       : std_logic_vector(0 to 31) := X"0000001C";
  constant C_EVR_REG_DATABUF_CONTROL  : std_logic_vector(0 to 31) := X"00000020";
  constant C_EVR_REG_TXDATABUF_CONTROL : std_logic_vector(0 to 31) := X"00000024";
  constant C_EVR_REG_TXSEGBUF_CONTROL : std_logic_vector(0 to 31) := X"00000028";
  constant C_EVR_REG_FW_VERSION       : std_logic_vector(0 to 31) := X"0000002C";
  constant C_EVR_REG_EVDCM_SAMPLE     : std_logic_vector(0 to 31) := X"00000030";
  constant C_EVR_REG_EVCNT_PRESC      : std_logic_vector(0 to 31) := X"00000040";
  constant C_EVR_REG_EVCNT_CONTROL    : std_logic_vector(0 to 31) := X"00000044";
  constant C_EVR_REG_USEC_DIVIDER     : std_logic_vector(0 to 31) := X"0000004C";
  constant C_EVR_REG_CLOCK_CONTROL    : std_logic_vector(0 to 31) := X"00000050";
  constant C_EVR_REG_SECONDS_SHIFT    : std_logic_vector(0 to 31) := X"0000005C";
  constant C_EVR_REG_SECONDS_COUNTER  : std_logic_vector(0 to 31) := X"00000060";
  constant C_EVR_REG_TSEVENT_COUNTER  : std_logic_vector(0 to 31) := X"00000064";
  constant C_EVR_REG_SECONDS_LATCH    : std_logic_vector(0 to 31) := X"00000068";
  constant C_EVR_REG_TSEVENT_LATCH    : std_logic_vector(0 to 31) := X"0000006C";
  constant C_EVR_REG_EVFIFO_SECONDS   : std_logic_vector(0 to 31) := X"00000070";
  constant C_EVR_REG_EVFIFO_TSEVENT   : std_logic_vector(0 to 31) := X"00000074";
  constant C_EVR_REG_EVFIFO_CODE      : std_logic_vector(0 to 31) := X"00000078";
  constant C_EVR_REG_LOG_STATUS       : std_logic_vector(0 to 31) := X"0000007C";
  constant C_EVR_REG_FRACDIV          : std_logic_vector(0 to 31) := X"00000080";
  constant C_EVR_REG_RX_INIT_PS       : std_logic_vector(0 to 31) := X"00000088";
  constant C_EVR_REG_GPIO_DIR         : std_logic_vector(0 to 31) := X"00000090";
  constant C_EVR_REG_GPIO_IN          : std_logic_vector(0 to 31) := X"00000094";
  constant C_EVR_REG_GPIO_OUT         : std_logic_vector(0 to 31) := X"00000098";
  constant C_EVR_REG_SPI_DATA         : std_logic_vector(0 to 31) := X"000000A0";
  constant C_EVR_REG_SPI_CONTROL      : std_logic_vector(0 to 31) := X"000000A4";
  constant C_EVR_REG_DC_TARGET        : std_logic_vector(0 to 31) := X"000000B0";
  constant C_EVR_REG_DC_VALUE         : std_logic_vector(0 to 31) := X"000000B4";
  constant C_EVR_REG_DC_INT_VALUE     : std_logic_vector(0 to 31) := X"000000B8";
  constant C_EVR_REG_DC_STATUS        : std_logic_vector(0 to 31) := X"000000BC";
  constant C_EVR_REG_TOPOLOGY_ADDR    : std_logic_vector(0 to 31) := X"000000C0";
  constant C_EVR_REG_TEST_OUT         : std_logic_vector(0 to 31) := X"000000CC";
  constant C_EVR_REG_TEST_IN          : std_logic_vector(0 to 31) := X"000000D0";
  constant C_EVR_REG_OVERRIDE_ADJUST  : std_logic_vector(0 to 31) := X"000000D4";
  constant C_EVR_REG_SEQRAM_CONTROL   : std_logic_vector(0 to 31) := X"000000E0";
  constant C_EVR_REG_PRESCALER_BASE   : std_logic_vector(0 to 31) := X"00000100";
  constant C_EVR_REG_PRESC_TRIG_BASE  : std_logic_vector(0 to 31) := X"00000140";
  constant C_EVR_REG_PRESC_CMP_HIGH   : integer := 25; -- last address bit to compare
  constant C_EVR_REG_PRESC_INDEX_LOW  : integer := 27;
  constant C_EVR_REG_PRESC_INDEX_HIGH : integer := 29;
  constant C_EVR_REG_DBUS_TRIG_BASE   : std_logic_vector(0 to 31) := X"00000180";
  constant C_EVR_REG_DBUS_CMP_HIGH    : integer := 24; -- last address bit to compare
  constant C_EVR_REG_DBUS_INDEX_LOW   : integer := 27;
  constant C_EVR_REG_DBUS_INDEX_HIGH  : integer := 29;
  constant C_EVR_REG_PULSE_BASE       : std_logic_vector(0 to 31) := X"00000200"; 
  constant C_EVR_REG_PULSE_CMP_HIGH   : integer := 22; -- last address bit to compare
  constant C_EVR_REG_PULSE_INDEX_LOW  : integer := 23;
  constant C_EVR_REG_PULSE_INDEX_HIGH : integer := 27;
  constant C_EVR_REG_FPOUT_BASE       : std_logic_vector(0 to 31) := X"00000400"; 
  constant C_EVR_REG_FPOUT_CMP_HIGH   : integer := 25; -- last address bit to compare
  constant C_EVR_REG_FPOUT_INDEX_LOW  : integer := 27;
  constant C_EVR_REG_FPOUT_INDEX_HIGH : integer := 29;
  constant C_EVR_REG_UNIV_BASE        : std_logic_vector(0 to 31) := X"00000440"; 
  constant C_EVR_REG_UNIV_CMP_HIGH    : integer := 25; -- last address bit to compare
  constant C_EVR_REG_UNIV_INDEX_LOW   : integer := 26;
  constant C_EVR_REG_UNIV_INDEX_HIGH  : integer := 29;
  constant C_EVR_REG_TBOUT_BASE       : std_logic_vector(0 to 31) := X"00000480"; 
  constant C_EVR_REG_TBOUT_CMP_HIGH   : integer := 25; -- last address bit to compare
  constant C_EVR_REG_TBOUT_INDEX_LOW  : integer := 26;
  constant C_EVR_REG_TBOUT_INDEX_HIGH : integer := 29;
  constant C_EVR_REG_BPOUT_BASE       : std_logic_vector(0 to 31) := X"000004C0"; 
  constant C_EVR_REG_BPOUT_CMP_HIGH   : integer := 25; -- last address bit to compare
  constant C_EVR_REG_BPOUT_INDEX_LOW  : integer := 26;
  constant C_EVR_REG_BPOUT_INDEX_HIGH : integer := 29;
  constant C_EVR_REG_FPIN_BASE        : std_logic_vector(0 to 31) := X"00000500"; 
  constant C_EVR_REG_FPIN_CMP_HIGH    : integer := 25; -- last address bit to compare
  constant C_EVR_REG_FPIN_INDEX_LOW   : integer := 29;
  constant C_EVR_REG_FPIN_INDEX_HIGH  : integer := 29;
  constant C_EVR_REG_DLY_BASE         : std_logic_vector(0 to 31) := X"00000580";
  constant C_EVR_REG_DLY_CMP_HIGH     : integer := 25; -- last address bit to compare
  constant C_EVR_REG_DLY_INDEX_LOW    : integer := 26;
  constant C_EVR_REG_DLY_INDEX_HIGH   : integer := 29;
  constant C_EVR_REG_CML_BASE         : std_logic_vector(0 to 31) := X"00000600";
  constant C_EVR_REG_CML_CMP_HIGH     : integer := 22; -- last address bit to compare
  constant C_EVR_REG_CML_INDEX_LOW    : integer := 24;
  constant C_EVR_REG_CML_INDEX_HIGH   : integer := 26;
  constant C_EVR_REG_CML_CTRL_SEL     : integer := 27;
  constant C_EVR_REG_CML_CTRL_ADDR    : std_logic_vector(0 to 2) := "100";
  constant C_EVR_REG_CML_PERIOD_ADDR  : std_logic_vector(0 to 2) := "101";
  constant C_EVR_REF_CML_SAMPL_ADDR   : std_logic_vector(0 to 2) := "110";
  constant C_EVR_DATABUF_BASE         : std_logic_vector(0 to 31) := X"00000800";
  constant C_EVR_DATABUF_CMP_HIGH     : integer := 20; -- last address bit to compare
  -- Diagnostic definitions
  constant C_DIAG_REG_CNT_INPUT       : std_logic_vector(0 to 31) := X"00001000";
  constant C_DIAG_REG_CNT_ENA         : std_logic_vector(0 to 31) := X"00001004";
  constant C_DIAG_REG_CNT_RESET       : std_logic_vector(0 to 31) := X"00001008";
  constant C_DIAG_REG_CNT_BASE        : std_logic_vector(0 to 31) := X"00001080";
  constant C_EVR_TXDATABUF_BASE       : std_logic_vector(0 to 31) := X"00001800";
  constant C_EVR_TXDATABUF_CMP_HIGH   : integer := 20; -- last address bit to compare
  constant C_EVR_REG_LOG_BASE         : std_logic_vector(0 to 31) := X"00002000";
  constant C_EVR_REG_LOG_CMP_HIGH     : integer := 18; -- last address bit to compare
  constant C_EVR_REG_MAP_BASE         : std_logic_vector(0 to 31) := X"00004000";
  constant C_EVR_REG_MAP_CMP_HIGH     : integer := 17; -- last address bit to compare
  constant C_EVR_REG_MAP_INDEX_LOW    : integer := 18;
  constant C_EVR_REG_MAP_INDEX_HIGH   : integer := 32 - C_EVENT_CODE_BITS - C_EVR_MAP_CODE_ABITS - 1;
  constant C_EVR_REG_CONFRAM_BASE     : std_logic_vector(0 to 31) := X"00008000";
  constant C_EVR_REG_CONFRAM_CMP_HIGH : integer := 21; -- last address bit to compare
  constant C_EVR_DATABUF_RXSZ_BASE    : std_logic_vector(0 to 31) := X"00008800";
  constant C_EVR_DATABUF_RXSZ_CMP_HIGH : integer := 21; -- last address bit to compare
  constant C_EVR_DATABUF_SIRQ_BASE    : std_logic_vector(0 to 31) := X"00008F80";
  constant C_EVR_DATABUF_CSF_BASE     : std_logic_vector(0 to 31) := X"00008FA0";
  constant C_EVR_DATABUF_OVF_BASE     : std_logic_vector(0 to 31) := X"00008FC0";
  constant C_EVR_DATABUF_RXF_BASE     : std_logic_vector(0 to 31) := X"00008FE0";
  constant C_EVR_DATABUF_FLAGCMP_HIGH : integer := 26; -- last address bit to compare
  constant C_EVR_DATABUF_DC_BASE      : std_logic_vector(0 to 31) := X"00009000";
  constant C_EVR_DATABUF_DC_CMP_HIGH  : integer := 19; -- last address bit to compare
  constant C_EVR_TXSEGBUF_BASE        : std_logic_vector(0 to 31) := X"0000A000";
  constant C_EVR_TXSEGBUF_CMP_HIGH    : integer := 20; -- last address bit to compare
  constant C_EVR_REG_SEQRAM_BASE       : std_logic_vector(0 to 31) := X"0000C000";
  constant C_EVR_REG_SEQRAM_CMP_HIGH   : integer := 17; -- last address bit to compare
  constant C_EVR_REG_SEQRAM_INDEX_LOW  : integer := 17;
  constant C_EVR_REG_SEQRAM_INDEX_HIGH : integer := 17;
  constant C_EVR_REG_CMLPAT_BASE       : std_logic_vector(0 to 31) := X"00020000";
  constant C_EVR_REG_CMLPAT_CMP_HIGH   : integer := 14; -- last address bit to compare
  constant C_EVR_REG_CMLPAT_INDEX_LOW  : integer := 15;
  constant C_EVR_REG_CMLPAT_INDEX_HIGH : integer := 17;

  -- Control Register bit mappings
  constant C_EVR_CTRL_MASTER_ENABLE   : integer := 31;
  constant C_EVR_CTRL_EVENT_FWD_ENA   : integer := 30;
  constant C_EVR_CTRL_TXLOOPBACK      : integer := 29;
  constant C_EVR_CTRL_RXLOOPBACK      : integer := 28;
  constant C_EVR_CTRL_OUTEN           : integer := 27;
  constant C_EVR_CTRL_SOFT_RESET      : integer := 26;
  constant C_EVR_CTRL_LE_MODE         : integer := 25;
  constant C_EVR_CTRL_GUNTX_INH_OVRDE : integer := 24;
  constant C_EVR_CTRL_USE_CDR         : integer := 23;
  constant C_EVR_CTRL_DC_MODE         : integer := 22;
  constant C_EVR_CTRL_TEST_MODE       : integer := 20;
  constant C_EVR_CTRL_OVERRIDE_MODE   : integer := 19;
  constant C_EVR_CTRL_PRESC_POLARITY  : integer := 15;
  constant C_EVR_CTRL_TS_CLOCK_DBUS   : integer := 14;
  constant C_EVR_CTRL_RESET_TIMESTAMP : integer := 13;
  constant C_EVR_CTRL_LATCH_TIMESTAMP : integer := 10;
  constant C_EVR_CTRL_MAP_RAM_ENABLE  : integer := 9;
  constant C_EVR_CTRL_MAP_RAM_SELECT  : integer := 8;
  constant C_EVR_CTRL_LOG_RESET       : integer := 7;
  constant C_EVR_CTRL_LOG_ENABLE      : integer := 6;
  constant C_EVR_CTRL_LOG_DISABLE     : integer := 5;
  constant C_EVR_CTRL_LOG_STOP_EV_EN  : integer := 4;
  constant C_EVR_CTRL_RESET_EVENTFIFO : integer := 3;
  constant C_EVR_CTRL_LE_MODE_MB      : integer := 1;
  -- Status Register bit mappings
  constant C_EVR_STATUS_DBUS_HIGH     : integer := 31;
  constant C_EVR_STATUS_GUNTX_INHIBIT : integer := 23;
  constant C_EVR_STATUS_LEGACY_VIO    : integer := 16;
  constant C_EVR_STATUS_MODDEF0       : integer := 7;
  constant C_EVR_STATUS_LINK_UP       : integer := 6;
  constant C_EVR_STATUS_LOG_STOPPED   : integer := 5;
  -- Interrupt Flag/Enable Register bit mappings
  constant C_EVR_IRQ_MASTER_ENABLE  : integer := 31;
  constant C_EVR_IRQ_PCICORE_ENABLE : integer := 30;
  constant C_EVR_IRQFLAG_SEQOVER    : integer := 20;
  constant C_EVR_IRQFLAG_SEQHALF    : integer := 16;
  constant C_EVR_IRQFLAG_SEQSTOP    : integer := 12;
  constant C_EVR_IRQFLAG_SEQSTART   : integer := 8;
  constant C_EVR_IRQFLAG_DATABUF_DC : integer := 7;
  constant C_EVR_IRQFLAG_LINKCHG    : integer := 6;
  constant C_EVR_IRQFLAG_DATABUF    : integer := 5;
  constant C_EVR_IRQFLAG_PULSE      : integer := 4;
  constant C_EVR_IRQFLAG_EVENT      : integer := 3;
  constant C_EVR_IRQFLAG_HEARTBEAT  : integer := 2;
  constant C_EVR_IRQFLAG_FIFOFULL   : integer := 1;
  constant C_EVR_IRQFLAG_VIOLATION  : integer := 0;
  -- SW Event Register bit mappings
  constant C_EVR_SWEVENT_PENDING    : integer := 9;
  constant C_EVR_SWEVENT_ENABLE     : integer := 8;
  constant C_EVR_SWEVENT_CODE_HIGH  : integer := 7;
  constant C_EVR_SWEVENT_CODE_LOW   : integer := 0;
  -- Databuffer Control Register bit mappings
  constant C_EVR_DATABUF_LOAD       : integer := 15;
  constant C_EVR_DATABUF_RECEIVING  : integer := 15;
  constant C_EVR_DATABUF_STOP       : integer := 14;
  constant C_EVR_DATABUF_RXREADY    : integer := 14;
  constant C_EVR_DATABUF_CHECKSUM   : integer := 13;
  constant C_EVR_DATABUF_MODE       : integer := 12;
  constant C_EVR_DATABUF_SIZEHIGH   : integer := 11;
  constant C_EVR_DATABUF_SIZELOW    : integer := 2;
  -- Databuffer Control Register bit mappings
  constant C_EVR_DATABUF_SADDRHIGH  : integer := 31;
  constant C_EVR_DATABUF_SADDRLOW   : integer := 24;
  constant C_EVR_TXDATABUF_COMPLETE : integer := 20;
  constant C_EVR_TXDATABUF_RUNNING  : integer := 19;
  constant C_EVR_TXDATABUF_TRIGGER  : integer := 18;
  constant C_EVR_TXDATABUF_ENA      : integer := 17;
  constant C_EVR_TXDATABUF_MODE     : integer := 16;
  constant C_EVR_TXDATABUF_SIZEHIGH : integer := 11;
  constant C_EVR_TXDATABUF_SIZELOW  : integer := 2;
  -- Clock Control Register bit mapppings
  constant C_EVR_CLKCTRL_PLLL         : integer := 31;
  constant C_EVR_CLKCTRL_BWSEL_HIGH   : integer := 30;
  constant C_EVR_CLKCTRL_BWSEL_LOW    : integer := 28;
  constant C_EVR_INT_CLK_MODE_H       : integer := 26;
  constant C_EVR_INT_CLK_MODE_L       : integer := 25;
  constant C_EVR_CLKCTRL_RECDCM_RUN    : integer := 15;
  constant C_EVR_CLKCTRL_RECDCM_INITD  : integer := 14;
  constant C_EVR_CLKCTRL_RECDCM_PSDONE : integer := 13;
  constant C_EVR_CLKCTRL_EVDCM_STOPPED : integer := 12;
  constant C_EVR_CLKCTRL_EVDCM_LOCKED : integer := 11;
  constant C_EVR_CLKCTRL_EVDCM_PSDONE : integer := 10;
  constant C_EVR_CLKCTRL_CGLOCK       : integer := 9;
  constant C_EVR_CLKCTRL_RECDCM_PSDEC : integer := 8;
  constant C_EVR_CLKCTRL_RECDCM_PSINC : integer := 7;
  constant C_EVR_CLKCTRL_RECDCM_RESET : integer := 6;
  constant C_EVR_CLKCTRL_EVDCM_PSDEC  : integer := 5;
  constant C_EVR_CLKCTRL_EVDCM_PSINC  : integer := 4;
  constant C_EVR_CLKCTRL_EVDCM_SRUN   : integer := 3;
  constant C_EVR_CLKCTRL_EVDCM_SRES   : integer := 2;
  constant C_EVR_CLKCTRL_EVDCM_RES    : integer := 1;
  constant C_EVR_CLKCTRL_USE_RXRECCLK : integer := 0;
  -- SPI Control Register bit mappings
  constant C_EVR_SPI_SSO              : integer := 0;
  constant C_EVR_SPI_OE               : integer := 1;
  constant C_EVR_SPI_ROE              : integer := 2;
  constant C_EVR_SPI_TOE              : integer := 3;
  constant C_EVR_SPI_TMT              : integer := 4;
  constant C_EVR_SPI_TRDY             : integer := 5;
  constant C_EVR_SPI_RRDY             : integer := 6;
  constant C_EVR_SPI_E                : integer := 7;
  -- Sequence RAM Control Register bit mappings
  constant C_EVR_SQRC_RUNNING         : integer := 25;
  constant C_EVR_SQRC_ENABLED         : integer := 24;
  constant C_EVR_SQRC_ALTERNATE       : integer := 22;
  constant C_EVR_SQRC_SWTRIGGER       : integer := 21;
  constant C_EVR_SQRC_SINGLE          : integer := 20;
  constant C_EVR_SQRC_RECYCLE         : integer := 19;
  constant C_EVR_SQRC_RESET           : integer := 18;
  constant C_EVR_SQRC_DISABLE         : integer := 17;
  constant C_EVR_SQRC_ENABLE          : integer := 16;
  constant C_EVR_SQRC_MASK_HIGH       : integer := 15;
  constant C_EVR_SQRC_MASK_LOW        : integer := 8;
  constant C_EVR_SQRC_TRIGSEL_LOW     : integer := 0;
  -- Sequence RAM Triggers
  constant C_EVR_SEQRAM_TRIGSEL_BITS  : integer := C_SIGNAL_MAP_BITS;
  constant C_EVR_SEQTRIG_MAX          : integer := 2**C_EVR_SEQRAM_TRIGSEL_BITS-1;
  type seqram_trigs_vector is array (integer range<>) of std_logic_vector(C_EVR_SEQTRIG_MAX downto 0);
--  constant C_EVR_SEQTRIG_EXT_BASE     : integer := 24;
  constant C_EVR_SEQTRIG_ALLWAYS      : integer := 62;
--  constant C_EVR_SEQTRIG_SWTRIGGER2   : integer := 18;
  constant C_EVR_SEQTRIG_SWTRIGGER    : integer := 61;
--  constant C_EVR_SEQTRIG_ACINPUT      : integer := 16;
  constant C_EVR_SEQTRIG_MXC_BASE     : integer := 0;
  -- Delay compensation status register bit mappings
  constant C_EVR_DC_INIT              : integer := 0;
  -- CML Control Register bit mappings
  constant C_EVR_CMLCTRL_GTX300_MODE  : integer := 11;
  constant C_EVR_CMLCTRL_GUNTX_MODE   : integer := 10;
  constant C_EVR_CMLCTRL_GUNTX_PHASE1 : integer := 9;
  constant C_EVR_CMLCTRL_GUNTX_PHASE0 : integer := 8;
  constant C_EVR_CMLCTRL_RECYCLE      : integer := 7;
  constant C_EVR_CMLCTRL_TRIG_LEVEL   : integer := 6;
  constant C_EVR_CMLCTRL_PATTERN_MODE : integer := 5;
  constant C_EVR_CMLCTRL_FREQ_MODE    : integer := 4;
  constant C_EVR_CMLCTRL_REFCLKSEL    : integer := 3;
  constant C_EVR_CMLCTRL_RESET        : integer := 2;
  constant C_EVR_CMLCTRL_POWERDOWN    : integer := 1;
  constant C_EVR_CMLCTRL_ENABLE       : integer := 0;
  -- Pulse Control Register bit mappings
  constant C_EVR_PULSE_MASK_HIGH      : integer := 31;
  constant C_EVR_PULSE_ENA_HIGH       : integer := 23;
  constant C_EVR_PULSE_OUT            : integer := 7;
  constant C_EVR_PULSE_SW_SET         : integer := 6;
  constant C_EVR_PULSE_SW_RESET       : integer := 5;
  constant C_EVR_PULSE_POLARITY       : integer := 4;
  constant C_EVR_PULSE_MAP_RESET_ENA  : integer := 3;
  constant C_EVR_PULSE_MAP_SET_ENA    : integer := 2;
  constant C_EVR_PULSE_MAP_TRIG_ENA   : integer := 1;
  constant C_EVR_PULSE_ENA            : integer := 0;
  -- Map RAM Internal event mappings
  constant C_EVR_MAP_SAVE_EVENT       : integer := 31;
  constant C_EVR_MAP_LATCH_TIMESTAMP  : integer := 30;
  constant C_EVR_MAP_LED_EVENT        : integer := 29;
  constant C_EVR_MAP_FORWARD_EVENT    : integer := 28;
  constant C_EVR_MAP_STOP_LOG         : integer := 27;
  constant C_EVR_MAP_LOG_EVENT        : integer := 26;
  constant C_EVR_MAP_HEARTBEAT_EVENT  : integer := 5;
  constant C_EVR_MAP_RESETPRESC_EVENT : integer := 4;
  constant C_EVR_MAP_TIMESTAMP_RESET  : integer := 3;
  constant C_EVR_MAP_TIMESTAMP_CLK    : integer := 2;
  constant C_EVR_MAP_SECONDS_1        : integer := 1;
  constant C_EVR_MAP_SECONDS_0        : integer := 0;
  -- FP Input Mapping bits
  constant C_EVR_FPIN_EXTEVENT_BASE   : integer := 0;
  constant C_EVR_FPIN_BACKEVENT_BASE  : integer := 8;
  constant C_EVR_FPIN_BACKDBUS_BASE   : integer := 16;
  constant C_EVR_FPIN_EXT_ENABLE      : integer := 24;
  constant C_EVR_FPIN_BACKEV_ENABLE   : integer := 25;
  constant C_EVR_FPIN_EXT_EDGE        : integer := 26;
  constant C_EVR_FPIN_EXTLEV_ENABLE   : integer := 27;
  constant C_EVR_FPIN_BACKLEV_ENABLE  : integer := 28;
  constant C_EVR_FPIN_EXTLEV_ACT      : integer := 29;
  constant C_EVR_FPIN_INPUT_STATE     : integer := 31;
  
  constant C_DIAG_REG_CNT_CMP_HIGH    : integer := 24;
  constant C_DIAG_COUNTERS_INDEX_LOW  : integer := 25;
  constant C_DIAG_COUNTERS_INDEX_HIGH : integer := 29;

  type gtx_data is array (natural range <>) of std_logic_vector(39 downto 0);

end evr_pkg;
