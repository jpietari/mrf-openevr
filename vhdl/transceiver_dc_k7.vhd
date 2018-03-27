---------------------------------------------------------------------------
--
--  File        : transceiver_dc_k7.vhd
--
--  Title       : Event Transceiver Multi-Gigabit Transceiver for Xilinx K7
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
use work.evr_pkg.all;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;

entity transceiver_dc_k7 is
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
    sys_clk         : in std_logic;   -- system bus clock
    REFCLK0P        : in std_logic;   -- MGTREFCLK0_P
    REFCLK0N        : in std_logic;   -- MGTREFCLK0_N
    REFCLK1P        : in std_logic;   -- MGTREFCLK1_P
    REFCLK1N        : in std_logic;   -- MGTREFCLK1N
    REFCLK_OUT      : out std_logic;  -- reference clock output
    recclk_out      : out std_logic;  -- Recovered clock, locked to EVG
    event_clk       : in std_logic;   -- event clock input (phase shifted by DCM)
    
    -- Receiver side connections
    event_rxd       : out std_logic_vector(7 downto 0); -- RX event code output
    dbus_rxd        : out std_logic_vector(7 downto 0); -- RX distributed bus bits
    databuf_rxd     : out std_logic_vector(7 downto 0); -- RX data buffer data
    databuf_rx_k    : out std_logic; -- RX data buffer K-character
    databuf_rx_ena  : out std_logic; -- RX data buffer data enable
    databuf_rx_mode : in std_logic;  -- RX data buffer mode, must be '1'
				     -- enabled for delay compensation mode
    dc_mode         : in std_logic;  -- delay compensation mode enable when '1'
    
    rx_link_ok      : out   std_logic; -- RX link OK
    rx_violation    : out   std_logic; -- RX violation detected
    rx_clear_viol   : in    std_logic; -- Clear RX violation
    rx_beacon       : out   std_logic; -- Received DC beacon
    tx_beacon       : out   std_logic; -- Transmitted DC beacon
    rx_int_beacon   : out   std_logic; -- Received DC beacon after DC FIFO

    delay_inc       : in    std_logic; -- Insert extra event in FIFO
    delay_dec       : in    std_logic; -- Drop event from FIFO
                                       -- These two control signals are used
				       -- only during the initial phase of
				       -- delay compensation adjustment
    
    reset           : in    std_logic; -- Transceiver reset

    -- Transmitter side connections
    event_txd       : in  std_logic_vector(7 downto 0); -- TX event code
    tx_event_ena    : out std_logic; -- 1 when event is sent out
                                     -- With backward events the beacon event
                                     -- has highest priority
    dbus_txd        : in  std_logic_vector(7 downto 0); -- TX distributed bus data
    databuf_txd     : in  std_logic_vector(7 downto 0); -- TX data buffer data
    databuf_tx_k    : in  std_logic; -- TX data buffer K-character
    databuf_tx_ena  : out std_logic; -- TX data buffer data enable
    databuf_tx_mode : in  std_logic; -- TX data buffer mode enabled when '1'
    
    RXN             : in    std_logic;
    RXP             : in    std_logic;

    TXN             : out   std_logic;
    TXP             : out   std_logic
    );
end transceiver_dc_k7;

architecture structure of transceiver_dc_k7 is

  signal vcc     : std_logic;
  signal gnd     : std_logic;
  signal gnd_vec : std_logic_vector(31 downto 0);
  signal tied_to_ground_i     :   std_logic;
  signal tied_to_ground_vec_i :   std_logic_vector(63 downto 0);
  signal tied_to_vcc_i        :   std_logic;

  signal REFCLK0       : std_logic;
  signal REFCLK1       : std_logic;
  signal tx_outclk     : std_logic;
  signal tx_refclk     : std_logic;
  signal refclk        : std_logic;
  
  signal rx_charisk    : std_logic_vector(1 downto 0);
  signal rx_rundisp    : std_logic_vector(1 downto 0);
  signal rx_commadet   : std_logic;
  signal rx_data       : std_logic_vector(15 downto 0);
  signal rx_disperr    : std_logic_vector(1 downto 0);
  signal rx_notintable : std_logic_vector(1 downto 0);
  signal rx_realign    : std_logic;
  signal rx_beacon_i   : std_logic;
  signal rxusrclk      : std_logic;
  signal txusrclk      : std_logic;
  signal rxcdrreset    : std_logic;

  signal RXEQMIX       : std_logic_vector(1 downto 0);
  
  signal link_ok         : std_logic;
  signal align_error     : std_logic;
  signal rx_error        : std_logic;
  signal rx_int_beacon_i : std_logic;
  signal rx_vio_usrclk   : std_logic;
  
  signal rx_link_ok_i    : std_logic;
  signal rx_error_i      : std_logic;
  
  signal tx_charisk    : std_logic_vector(1 downto 0);
  signal tx_data       : std_logic_vector(15 downto 0);

  signal rx_powerdown   : std_logic;
  signal tx_powerdown   : std_logic;

  signal databuf_rxd_i : std_logic_vector(7 downto 0);
  signal databuf_rx_k_i    : std_logic;

  signal fifo_do       : std_logic_vector(63 downto 0);
  signal fifo_dop      : std_logic_vector(7 downto 0);
  signal fifo_rden     : std_logic;
  signal fifo_rst      : std_logic;
  signal fifo_wren     : std_logic;
  signal fifo_di       : std_logic_vector(63 downto 0);
  signal fifo_dip      : std_logic_vector(7 downto 0);

  signal tx_fifo_do    : std_logic_vector(31 downto 0);
  signal tx_fifo_dop   : std_logic_vector(3 downto 0);
  signal tx_fifo_rden  : std_logic;
  signal tx_fifo_rderr : std_logic;
  signal tx_fifo_empty : std_logic;
  signal tx_fifo_rst   : std_logic;
  signal tx_fifo_wren  : std_logic;
  signal tx_fifo_di    : std_logic_vector(31 downto 0);
  signal tx_fifo_dip   : std_logic_vector(3 downto 0);

  signal tx_event_ena_i : std_logic;
  
  -- RX Datapath signals
  signal rxdata_i                         :   std_logic_vector(63 downto 0);      
  signal rxchariscomma_float_i            :   std_logic_vector(5 downto 0);
  signal rxcharisk_float_i                :   std_logic_vector(5 downto 0);
  signal rxdisperr_float_i                :   std_logic_vector(5 downto 0);
  signal rxnotintable_float_i             :   std_logic_vector(5 downto 0);
  signal rxrundisp_float_i                :   std_logic_vector(5 downto 0);

  -- TX Datapath signals
  signal txdata_i                         :   std_logic_vector(63 downto 0);
  signal txkerr_float_i                   :   std_logic_vector(5 downto 0);
  signal txrundisp_float_i                :   std_logic_vector(5 downto 0);
  signal txbufstatus_i                    :   std_logic_vector(1 downto 0);  

  signal CPLLFBCLKLOST_out : std_logic;
  signal CPLLLOCK_out : std_logic;
  signal CPLLREFCLKSEL_in : std_logic_vector(2 downto 0);
  signal CPLLREFCLKLOST_out : std_logic;
  signal CPLLRESET_in : std_logic;
  signal RXUSERRDY_in : std_logic;
  signal RXCDRHOLD_in : std_logic;
  signal RXCDRLOCK_out : std_logic;
  signal RXDISPERR_out : std_logic_vector(1 downto 0);
  signal RXNOTINTABLE_out : std_logic_vector(1 downto 0);
  signal RXBUFRESET_in : std_logic;
  signal RXDLYEN_in : std_logic;
  signal RXDLYSRESET_in : std_logic;
  signal RXDLYSRESETDONE_out : std_logic;
  signal RXPHALIGN_in : std_logic;
  signal RXPHALIGNDONE_out : std_logic;
  signal RXPHALIGNEN_in : std_logic;
  signal RXPHDLYRESET_in : std_logic;
  signal RXPHMONITOR_out : std_logic_vector(4 downto 0);
  signal RXPHSLIPMONITOR_out : std_logic_vector(4 downto 0);
  signal RXBYTEISALIGNED_out : std_logic;
  signal RXBYTEREALIGN_out : std_logic;
  signal RXCOMMADET_out : std_logic;
  signal RXDFELPMRESET_in : std_logic;
  signal RXOUTCLK_out : std_logic;
  signal RXOUTCLKPCS_out : std_logic; 
  signal GTRXRESET_in : std_logic;
  signal RXPCSRESET_in : std_logic;
  signal RXPMARESET_in : std_logic;
  signal RXLPMEN_in : std_logic;
  signal RXPOLARITY_in : std_logic;
  signal RXSLIDE_in : std_logic;
  signal RXCHARISK_out : std_logic_vector(1 downto 0);
  signal RXRESETDONE_out : std_logic;
  signal GTTXRESET_in : std_logic;
  signal TXUSERRDY_in : std_logic;
  signal TXDLYEN_in : std_logic;
  signal TXDLYSRESET_in : std_logic;
  signal TXPHALIGN_in : std_logic;
  signal TXPHALIGNEN_in : std_logic;
  signal TXPHDLYRESET_in : std_logic;
  signal TXPHINIT_in : std_logic;
  signal TXOUTCLK_out : std_logic;
  signal TXOUTCLKFABRIC_out : std_logic;
  signal TXOUTCLKPCS_out : std_logic;
  signal TXPCSRESET_in : std_logic;
  signal TXPMARESET_in : std_logic;
  signal TXCHARISK_in : std_logic_vector(1 downto 0);
  signal TXRESETDONE_out : std_logic;
  signal TXPOLARITY_in : std_logic;
  
  -- RX Datapath signals
  signal rxdata0_i                        :   std_logic_vector(31 downto 0);      
  signal rxcharisk0_float_i               :   std_logic_vector(1 downto 0);
  signal rxdisperr0_float_i               :   std_logic_vector(1 downto 0);
  signal rxnotintable0_float_i            :   std_logic_vector(1 downto 0);
  signal rxrundisp0_float_i               :   std_logic_vector(1 downto 0);
  
  -- TX Datapath signals
  signal txdata0_i                        :   std_logic_vector(31 downto 0);
  signal txkerr0_float_i                  :   std_logic_vector(1 downto 0);
  signal txrundisp0_float_i               :   std_logic_vector(1 downto 0);
   

  -- RX Datapath signals
  signal rxdata1_i                        :   std_logic_vector(31 downto 0);      
  signal rxcharisk1_float_i               :   std_logic_vector(1 downto 0);
  signal rxdisperr1_float_i               :   std_logic_vector(1 downto 0);
  signal rxnotintable1_float_i            :   std_logic_vector(1 downto 0);
  signal rxrundisp1_float_i               :   std_logic_vector(1 downto 0);
    

  -- TX Datapath signals
  signal txdata1_i                        :   std_logic_vector(31 downto 0);
  signal txkerr1_float_i                  :   std_logic_vector(1 downto 0);
  signal txrundisp1_float_i               :   std_logic_vector(1 downto 0);

  signal phase_acc    : std_logic_vector(6 downto 0);
  signal phase_acc_en : std_logic;
  signal drpclk  : std_logic;
  signal drpaddr : std_logic_vector(8 downto 0);
  signal drpdi   : std_logic_vector(15 downto 0);
  signal drpdo   : std_logic_vector(15 downto 0);
  signal drpen   : std_logic;
  signal drpwe   : std_logic;
  signal drprdy  : std_logic;

  signal TRIG0 : std_logic_vector(255 downto 0);
  
  COMPONENT ila_0
    PORT (
      clk : IN STD_LOGIC;
      probe0 : IN STD_LOGIC_VECTOR(255 DOWNTO 0)
      );
  END COMPONENT;

begin

  -- ILA debug core
  i_ila : ila_0
    port map (
      CLK => txusrclk,
      probe0 => TRIG0);

  gtxe2_X0Y0_i :GTXE2_CHANNEL
    generic map
    (

        --_______________________ Simulation-Only Attributes ___________________

        SIM_RECEIVER_DETECT_PASS   =>      ("TRUE"),
        SIM_RESET_SPEEDUP          =>      ("TRUE"),
        SIM_TX_EIDLE_DRIVE_LEVEL   =>      ("X"),
        SIM_CPLLREFCLK_SEL         =>      ("001"),
        SIM_VERSION                =>      ("4.0"), 
        

       ------------------RX Byte and Word Alignment Attributes---------------
        ALIGN_COMMA_DOUBLE                      =>     ("FALSE"),
        ALIGN_COMMA_ENABLE                      =>     ("1111111111"),
        ALIGN_COMMA_WORD                        =>     (1),
        ALIGN_MCOMMA_DET                        =>     ("TRUE"),
        ALIGN_MCOMMA_VALUE                      =>     ("1010000011"),
        ALIGN_PCOMMA_DET                        =>     ("TRUE"),
        ALIGN_PCOMMA_VALUE                      =>     ("0101111100"),
        SHOW_REALIGN_COMMA                      =>     ("FALSE"),
        RXSLIDE_AUTO_WAIT                       =>     (7),
        RXSLIDE_MODE                            =>     ("OFF"),
        RX_SIG_VALID_DLY                        =>     (10),

       ------------------RX 8B/10B Decoder Attributes---------------
        RX_DISPERR_SEQ_MATCH                    =>     ("TRUE"),
        DEC_MCOMMA_DETECT                       =>     ("TRUE"),
        DEC_PCOMMA_DETECT                       =>     ("TRUE"),
        DEC_VALID_COMMA_ONLY                    =>     ("FALSE"),

       ------------------------RX Clock Correction Attributes----------------------
        CBCC_DATA_SOURCE_SEL                    =>     ("DECODED"),
        CLK_COR_SEQ_2_USE                       =>     ("FALSE"),
        CLK_COR_KEEP_IDLE                       =>     ("FALSE"),
        CLK_COR_MAX_LAT                         =>     (9),
        CLK_COR_MIN_LAT                         =>     (7),
        CLK_COR_PRECEDENCE                      =>     ("TRUE"),
        CLK_COR_REPEAT_WAIT                     =>     (0),
        CLK_COR_SEQ_LEN                         =>     (1),
        CLK_COR_SEQ_1_ENABLE                    =>     ("1111"),
        CLK_COR_SEQ_1_1                         =>     ("0000000000"),
        CLK_COR_SEQ_1_2                         =>     ("0000000000"),
        CLK_COR_SEQ_1_3                         =>     ("0000000000"),
        CLK_COR_SEQ_1_4                         =>     ("0000000000"),
        CLK_CORRECT_USE                         =>     ("FALSE"),
        CLK_COR_SEQ_2_ENABLE                    =>     ("1111"),
        CLK_COR_SEQ_2_1                         =>     ("0000000000"),
        CLK_COR_SEQ_2_2                         =>     ("0000000000"),
        CLK_COR_SEQ_2_3                         =>     ("0000000000"),
        CLK_COR_SEQ_2_4                         =>     ("0000000000"),

       ------------------------RX Channel Bonding Attributes----------------------
        CHAN_BOND_KEEP_ALIGN                    =>     ("FALSE"),
        CHAN_BOND_MAX_SKEW                      =>     (1),
        CHAN_BOND_SEQ_LEN                       =>     (1),
        CHAN_BOND_SEQ_1_1                       =>     ("0000000000"),
        CHAN_BOND_SEQ_1_2                       =>     ("0000000000"),
        CHAN_BOND_SEQ_1_3                       =>     ("0000000000"),
        CHAN_BOND_SEQ_1_4                       =>     ("0000000000"),
        CHAN_BOND_SEQ_1_ENABLE                  =>     ("1111"),
        CHAN_BOND_SEQ_2_1                       =>     ("0000000000"),
        CHAN_BOND_SEQ_2_2                       =>     ("0000000000"),
        CHAN_BOND_SEQ_2_3                       =>     ("0000000000"),
        CHAN_BOND_SEQ_2_4                       =>     ("0000000000"),
        CHAN_BOND_SEQ_2_ENABLE                  =>     ("1111"),
        CHAN_BOND_SEQ_2_USE                     =>     ("FALSE"),
        FTS_DESKEW_SEQ_ENABLE                   =>     ("1111"),
        FTS_LANE_DESKEW_CFG                     =>     ("1111"),
        FTS_LANE_DESKEW_EN                      =>     ("FALSE"),

       ---------------------------RX Margin Analysis Attributes----------------------------
        ES_CONTROL                              =>     ("000000"),
        ES_ERRDET_EN                            =>     ("FALSE"),
        ES_EYE_SCAN_EN                          =>     ("TRUE"),
        ES_HORZ_OFFSET                          =>     (x"000"),
        ES_PMA_CFG                              =>     ("0000000000"),
        ES_PRESCALE                             =>     ("00000"),
        ES_QUALIFIER                            =>     (x"00000000000000000000"),
        ES_QUAL_MASK                            =>     (x"00000000000000000000"),
        ES_SDATA_MASK                           =>     (x"00000000000000000000"),
        ES_VERT_OFFSET                          =>     ("000000000"),

       -------------------------FPGA RX Interface Attributes-------------------------
        RX_DATA_WIDTH                           =>     (20),

       ---------------------------PMA Attributes----------------------------
        OUTREFCLK_SEL_INV                       =>     ("11"),
        PMA_RSV                                 =>     (PMA_RSV_IN),
        PMA_RSV2                                =>     (x"2050"),
        PMA_RSV3                                =>     ("00"),
        PMA_RSV4                                =>     (x"00000000"),
        RX_BIAS_CFG                             =>     ("000000000100"),
        DMONITOR_CFG                            =>     (x"000A00"),
        RX_CM_SEL                               =>     ("11"),
        RX_CM_TRIM                              =>     ("010"),
        RX_DEBUG_CFG                            =>     ("000000000000"),
        RX_OS_CFG                               =>     ("0000010000000"),
        TERM_RCAL_CFG                           =>     ("10000"),
        TERM_RCAL_OVRD                          =>     ('0'),
        TST_RSV                                 =>     (x"00000000"),
        RX_CLK25_DIV                            =>     (5),
        TX_CLK25_DIV                            =>     (5),
        UCODEER_CLR                             =>     ('0'),

       ---------------------------PCI Express Attributes----------------------------
        PCS_PCIE_EN                             =>     ("FALSE"),

       ---------------------------PCS Attributes----------------------------
        PCS_RSVD_ATTR                           =>     (PCS_RSVD_ATTR_IN),

       -------------RX Buffer Attributes------------
        RXBUF_ADDR_MODE                         =>     ("FAST"),
        RXBUF_EIDLE_HI_CNT                      =>     ("1000"),
        RXBUF_EIDLE_LO_CNT                      =>     ("0000"),
        RXBUF_EN                                =>     ("FALSE"),
        RX_BUFFER_CFG                           =>     ("000000"),
        RXBUF_RESET_ON_CB_CHANGE                =>     ("TRUE"),
        RXBUF_RESET_ON_COMMAALIGN               =>     ("FALSE"),
        RXBUF_RESET_ON_EIDLE                    =>     ("FALSE"),
        RXBUF_RESET_ON_RATE_CHANGE              =>     ("TRUE"),
        RXBUFRESET_TIME                         =>     ("00001"),
        RXBUF_THRESH_OVFLW                      =>     (61),
        RXBUF_THRESH_OVRD                       =>     ("FALSE"),
        RXBUF_THRESH_UNDFLW                     =>     (4),
        RXDLY_CFG                               =>     (x"001F"),
        RXDLY_LCFG                              =>     (x"030"),
        RXDLY_TAP_CFG                           =>     (x"0000"),
        RXPH_CFG                                =>     (x"000000"),
        RXPHDLY_CFG                             =>     (x"084020"),
        RXPH_MONITOR_SEL                        =>     ("00000"),
        RX_XCLK_SEL                             =>     ("RXUSR"),
        RX_DDI_SEL                              =>     ("000000"),
        RX_DEFER_RESET_BUF_EN                   =>     ("TRUE"),

       -----------------------CDR Attributes-------------------------

       --For GTX only: Display Port, HBR/RBR- set RXCDR_CFG=72'h0380008bff40200002

       --For GTX only: Display Port, HBR2 -   set RXCDR_CFG=72'h03000023ff10200020
        RXCDR_CFG                               =>     (x"03000023ff40200020"),
        RXCDR_FR_RESET_ON_EIDLE                 =>     ('0'),
        RXCDR_HOLD_DURING_EIDLE                 =>     ('0'),
        RXCDR_PH_RESET_ON_EIDLE                 =>     ('0'),
        RXCDR_LOCK_CFG                          =>     ("010101"),

       -------------------RX Initialization and Reset Attributes-------------------
        RXCDRFREQRESET_TIME                     =>     ("00001"),
        RXCDRPHRESET_TIME                       =>     ("00001"),
        RXISCANRESET_TIME                       =>     ("00001"),
        RXPCSRESET_TIME                         =>     ("00001"),
        RXPMARESET_TIME                         =>     ("00011"),

       -------------------RX OOB Signaling Attributes-------------------
        RXOOB_CFG                               =>     ("0000110"),

       -------------------------RX Gearbox Attributes---------------------------
        RXGEARBOX_EN                            =>     ("FALSE"),
        GEARBOX_MODE                            =>     ("000"),

       -------------------------PRBS Detection Attribute-----------------------
        RXPRBS_ERR_LOOPBACK                     =>     ('0'),

       -------------Power-Down Attributes----------
        PD_TRANS_TIME_FROM_P2                   =>     (x"03c"),
        PD_TRANS_TIME_NONE_P2                   =>     (x"3c"),
        PD_TRANS_TIME_TO_P2                     =>     (x"64"),

       -------------RX OOB Signaling Attributes----------
        SAS_MAX_COM                             =>     (64),
        SAS_MIN_COM                             =>     (36),
        SATA_BURST_SEQ_LEN                      =>     ("1111"),
        SATA_BURST_VAL                          =>     ("100"),
        SATA_EIDLE_VAL                          =>     ("100"),
        SATA_MAX_BURST                          =>     (8),
        SATA_MAX_INIT                           =>     (21),
        SATA_MAX_WAKE                           =>     (7),
        SATA_MIN_BURST                          =>     (4),
        SATA_MIN_INIT                           =>     (12),
        SATA_MIN_WAKE                           =>     (4),

       -------------RX Fabric Clock Output Control Attributes----------
        TRANS_TIME_RATE                         =>     (x"0E"),

       --------------TX Buffer Attributes----------------
        TXBUF_EN                                =>     ("TRUE"),
        TXBUF_RESET_ON_RATE_CHANGE              =>     ("TRUE"),
        TXDLY_CFG                               =>     (x"001F"),
        TXDLY_LCFG                              =>     (x"034"),
        TXDLY_TAP_CFG                           =>     (x"0000"),
        TXPH_CFG                                =>     (x"0780"),
        TXPHDLY_CFG                             =>     (x"084020"),
        TXPH_MONITOR_SEL                        =>     ("00000"),
        TX_XCLK_SEL                             =>     ("TXOUT"),

       -------------------------FPGA TX Interface Attributes-------------------------
        TX_DATA_WIDTH                           =>     (20),

       -------------------------TX Configurable Driver Attributes-------------------------
        TX_DEEMPH0                              =>     ("00000"),
        TX_DEEMPH1                              =>     ("00000"),
        TX_EIDLE_ASSERT_DELAY                   =>     ("110"),
        TX_EIDLE_DEASSERT_DELAY                 =>     ("100"),
        TX_LOOPBACK_DRIVE_HIZ                   =>     ("FALSE"),
        TX_MAINCURSOR_SEL                       =>     ('0'),
        TX_DRIVE_MODE                           =>     ("DIRECT"),
        TX_MARGIN_FULL_0                        =>     ("1001110"),
        TX_MARGIN_FULL_1                        =>     ("1001001"),
        TX_MARGIN_FULL_2                        =>     ("1000101"),
        TX_MARGIN_FULL_3                        =>     ("1000010"),
        TX_MARGIN_FULL_4                        =>     ("1000000"),
        TX_MARGIN_LOW_0                         =>     ("1000110"),
        TX_MARGIN_LOW_1                         =>     ("1000100"),
        TX_MARGIN_LOW_2                         =>     ("1000010"),
        TX_MARGIN_LOW_3                         =>     ("1000000"),
        TX_MARGIN_LOW_4                         =>     ("1000000"),

       -------------------------TX Gearbox Attributes--------------------------
        TXGEARBOX_EN                            =>     ("FALSE"),

       -------------------------TX Initialization and Reset Attributes--------------------------
        TXPCSRESET_TIME                         =>     ("00001"),
        TXPMARESET_TIME                         =>     ("00001"),

       -------------------------TX Receiver Detection Attributes--------------------------
        TX_RXDETECT_CFG                         =>     (x"1832"),
        TX_RXDETECT_REF                         =>     ("100"),

       ----------------------------CPLL Attributes----------------------------
        CPLL_CFG                                =>     (x"BC07DC"),
        CPLL_FBDIV                              =>     (4),
        CPLL_FBDIV_45                           =>     (5),
        CPLL_INIT_CFG                           =>     (x"00001E"),
        CPLL_LOCK_CFG                           =>     (x"01E8"),
        CPLL_REFCLK_DIV                         =>     (1),
        RXOUT_DIV                               =>     (2),
        TXOUT_DIV                               =>     (2),
        SATA_CPLL_CFG                           =>     ("VCO_3000MHZ"),

       --------------RX Initialization and Reset Attributes-------------
        RXDFELPMRESET_TIME                      =>     ("0001111"),

       --------------RX Equalizer Attributes-------------
        RXLPM_HF_CFG                            =>     ("00000011110000"),
        RXLPM_LF_CFG                            =>     ("00000011110000"),
        RX_DFE_GAIN_CFG                         =>     (x"020FEA"),
        RX_DFE_H2_CFG                           =>     ("000000000000"),
        RX_DFE_H3_CFG                           =>     ("000001000000"),
        RX_DFE_H4_CFG                           =>     ("00011110000"),
        RX_DFE_H5_CFG                           =>     ("00011100000"),
        RX_DFE_KL_CFG                           =>     ("0000011111110"),
        RX_DFE_LPM_CFG                          =>     (x"0954"),
        RX_DFE_LPM_HOLD_DURING_EIDLE            =>     ('0'),
        RX_DFE_UT_CFG                           =>     ("10001111000000000"),
        RX_DFE_VP_CFG                           =>     ("00011111100000011"),

       -------------------------Power-Down Attributes-------------------------
        RX_CLKMUX_PD                            =>     ('1'),
        TX_CLKMUX_PD                            =>     ('1'),

       -------------------------FPGA RX Interface Attribute-------------------------
        RX_INT_DATAWIDTH                        =>     (0),

       -------------------------FPGA TX Interface Attribute-------------------------
        TX_INT_DATAWIDTH                        =>     (0),

       ------------------TX Configurable Driver Attributes---------------
        TX_QPI_STATUS_EN                        =>     ('0'),

       -------------------------RX Equalizer Attributes--------------------------
        RX_DFE_KL_CFG2                          =>     (RX_DFE_KL_CFG2_IN),
        RX_DFE_XYD_CFG                          =>     ("0000000000000"),

       -------------------------TX Configurable Driver Attributes--------------------------
        TX_PREDRIVER_MODE                       =>     ('0')


    )
    port map
    (
        --------------------------------- CPLL Ports -------------------------------
        CPLLFBCLKLOST                   =>      CPLLFBCLKLOST_out,
        CPLLLOCK                        =>      CPLLLOCK_out,
        CPLLLOCKDETCLK                  =>      sys_clk,
        CPLLLOCKEN                      =>      vcc,
        CPLLPD                          =>      gnd,
        CPLLREFCLKLOST                  =>      CPLLREFCLKLOST_out,
        CPLLREFCLKSEL                   =>      CPLLREFCLKSEL_in,
        CPLLRESET                       =>      CPLLRESET_in,
        GTRSVD                          =>      "0000000000000000",
        PCSRSVDIN                       =>      "0000000000000000",
        PCSRSVDIN2                      =>      "00000",
        PMARSVDIN                       =>      "00000",
        PMARSVDIN2                      =>      "00000",
        TSTIN                           =>      "11111111111111111111",
        TSTOUT                          =>      open,
        ---------------------------------- Channel ---------------------------------
        CLKRSVD                         =>      "0000",
        -------------------------- Channel - Clocking Ports ------------------------
        GTGREFCLK                       =>      gnd,
        GTNORTHREFCLK0                  =>      gnd,
        GTNORTHREFCLK1                  =>      gnd,
        GTREFCLK0                       =>      REFCLK0,
        GTREFCLK1                       =>      REFCLK1,
        GTSOUTHREFCLK0                  =>      gnd,
        GTSOUTHREFCLK1                  =>      gnd,
        ---------------------------- Channel - DRP Ports  --------------------------
        DRPADDR                         =>      drpaddr,
        DRPCLK                          =>      drpclk,
        DRPDI                           =>      drpdi,
        DRPDO                           =>      drpdo,
        DRPEN                           =>      drpen,
        DRPRDY                          =>      drprdy,
        DRPWE                           =>      drpwe,
       ------------------------------- Clocking Ports -----------------------------
        GTREFCLKMONITOR                 =>      open,
        QPLLCLK                         =>      gnd,
        QPLLREFCLK                      =>      gnd,
        RXSYSCLKSEL                     =>      "00",
        TXSYSCLKSEL                     =>      "00",
        --------------------------- Digital Monitor Ports --------------------------
        DMONITOROUT                     =>      open,
        ----------------- FPGA TX Interface Datapath Configuration  ----------------
        TX8B10BEN                       =>      vcc,
        ------------------------------- Loopback Ports -----------------------------
        LOOPBACK                        =>      gnd_vec(2 downto 0),
        ----------------------------- PCI Express Ports ----------------------------
        PHYSTATUS                       =>      open,
        RXRATE                          =>      gnd_vec(2 downto 0),
        RXVALID                         =>      open,
        ------------------------------ Power-Down Ports ----------------------------
        RXPD                            =>      "00",
        TXPD                            =>      "00",
        -------------------------- RX 8B/10B Decoder Ports -------------------------
        SETERRSTATUS                    =>      gnd,
        --------------------- RX Initialization and Reset Ports --------------------
        EYESCANRESET                    =>      gnd,
        RXUSERRDY                       =>      RXUSERRDY_in,
        -------------------------- RX Margin Analysis Ports ------------------------
        EYESCANDATAERROR                =>      open,
        EYESCANMODE                     =>      gnd,
        EYESCANTRIGGER                  =>      gnd,
        ------------------------- Receive Ports - CDR Ports ------------------------
        RXCDRFREQRESET                  =>      gnd,
        RXCDRHOLD                       =>      gnd,
        RXCDRLOCK                       =>      RXCDRLOCK_out,
        RXCDROVRDEN                     =>      gnd,
        RXCDRRESET                      =>      gnd,
        RXCDRRESETRSV                   =>      gnd,
        ------------------- Receive Ports - Clock Correction Ports -----------------
        RXCLKCORCNT                     =>      open,
        ---------- Receive Ports - FPGA RX Interface Datapath Configuration --------
        RX8B10BEN                       =>      vcc,
        ------------------ Receive Ports - FPGA RX Interface Ports -----------------
        RXUSRCLK                        =>      rxusrclk,
        RXUSRCLK2                       =>      rxusrclk,
        ------------------ Receive Ports - FPGA RX interface Ports -----------------
        RXDATA                          =>      rxdata_i,
        ------------------- Receive Ports - Pattern Checker Ports ------------------
        RXPRBSERR                       =>      open,
        RXPRBSSEL                       =>      gnd_vec(2 downto 0),
        ------------------- Receive Ports - Pattern Checker ports ------------------
        RXPRBSCNTRESET                  =>      gnd,
        -------------------- Receive Ports - RX  Equalizer Ports -------------------
        RXDFEXYDEN                      =>      gnd,
        RXDFEXYDHOLD                    =>      gnd,
        RXDFEXYDOVRDEN                  =>      gnd,
        ------------------ Receive Ports - RX 8B/10B Decoder Ports -----------------
        RXDISPERR(7 downto 2)           =>      rxdisperr_float_i,
        RXDISPERR(1 downto 0)           =>      rx_disperr,
        RXNOTINTABLE(7 downto 2)        =>      rxnotintable_float_i,
        RXNOTINTABLE(1 downto 0)        =>      rx_notintable,
        --------------------------- Receive Ports - RX AFE -------------------------
        GTXRXP                          =>      RXP,
        ------------------------ Receive Ports - RX AFE Ports ----------------------
        GTXRXN                          =>      RXN,
        ------------------- Receive Ports - RX Buffer Bypass Ports -----------------
        RXBUFRESET                      =>      gnd,
        RXBUFSTATUS                     =>      open,
        RXDDIEN                         =>      vcc,
        RXDLYBYPASS                     =>      gnd,
        RXDLYEN                         =>      RXDLYEN_in,
        RXDLYOVRDEN                     =>      gnd,
        RXDLYSRESET                     =>      RXDLYSRESET_in,
        RXDLYSRESETDONE                 =>      RXDLYSRESETDONE_out,
        RXPHALIGN                       =>      RXPHALIGN_in,
        RXPHALIGNDONE                   =>      RXPHALIGNDONE_out,
        RXPHALIGNEN                     =>      RXPHALIGNEN_in,
        RXPHDLYPD                       =>      gnd,
        RXPHDLYRESET                    =>      RXPHDLYRESET_in,
        RXPHMONITOR                     =>      RXPHMONITOR_out,
        RXPHOVRDEN                      =>      gnd,
        RXPHSLIPMONITOR                 =>      RXPHSLIPMONITOR_out,
        RXSTATUS                        =>      open,
        -------------- Receive Ports - RX Byte and Word Alignment Ports ------------
        RXBYTEISALIGNED                 =>      RXBYTEISALIGNED_out,
        RXBYTEREALIGN                   =>      RXBYTEREALIGN_out,
        RXCOMMADET                      =>      RXCOMMADET_out,
        RXCOMMADETEN                    =>      gnd,
        RXMCOMMAALIGNEN                 =>      gnd,
        RXPCOMMAALIGNEN                 =>      gnd,
        ------------------ Receive Ports - RX Channel Bonding Ports ----------------
        RXCHANBONDSEQ                   =>      open,
        RXCHBONDEN                      =>      gnd,
        RXCHBONDLEVEL                   =>      gnd_vec(2 downto 0),
        RXCHBONDMASTER                  =>      gnd,
        RXCHBONDO                       =>      open,
        RXCHBONDSLAVE                   =>      gnd,
        ----------------- Receive Ports - RX Channel Bonding Ports  ----------------
        RXCHANISALIGNED                 =>      open,
        RXCHANREALIGN                   =>      open,
        --------------------- Receive Ports - RX Equalizer Ports -------------------
        RXDFEAGCHOLD                    =>      gnd,
        RXDFEAGCOVRDEN                  =>      gnd,
        RXDFECM1EN                      =>      gnd,
        RXDFELFHOLD                     =>      gnd,
        RXDFELFOVRDEN                   =>      vcc,
        RXDFELPMRESET                   =>      RXDFELPMRESET_in,
        RXDFETAP2HOLD                   =>      gnd,
        RXDFETAP2OVRDEN                 =>      gnd,
        RXDFETAP3HOLD                   =>      gnd,
        RXDFETAP3OVRDEN                 =>      gnd,
        RXDFETAP4HOLD                   =>      gnd,
        RXDFETAP4OVRDEN                 =>      gnd,
        RXDFETAP5HOLD                   =>      gnd,
        RXDFETAP5OVRDEN                 =>      gnd,
        RXDFEUTHOLD                     =>      gnd,
        RXDFEUTOVRDEN                   =>      gnd,
        RXDFEVPHOLD                     =>      gnd,
        RXDFEVPOVRDEN                   =>      gnd,
        RXDFEVSEN                       =>      gnd,
        RXLPMLFKLOVRDEN                 =>      gnd,
        RXMONITOROUT                    =>      open,
        RXMONITORSEL                    =>      "01",
        RXOSHOLD                        =>      gnd,
        RXOSOVRDEN                      =>      gnd,
        --------------------- Receive Ports - RX Equilizer Ports -------------------
        RXLPMHFHOLD                     =>      gnd,
        RXLPMHFOVRDEN                   =>      gnd,
        RXLPMLFHOLD                     =>      gnd,
        ------------ Receive Ports - RX Fabric ClocK Output Control Ports ----------
        RXRATEDONE                      =>      open,
        --------------- Receive Ports - RX Fabric Output Control Ports -------------
        RXOUTCLK                        =>      RXOUTCLK_out,
        RXOUTCLKFABRIC                  =>      open,
        RXOUTCLKPCS                     =>      RXOUTCLKPCS_out,
        RXOUTCLKSEL                     =>      "010",
        ---------------------- Receive Ports - RX Gearbox Ports --------------------
        RXDATAVALID                     =>      open,
        RXHEADER                        =>      open,
        RXHEADERVALID                   =>      open,
        RXSTARTOFSEQ                    =>      open,
        --------------------- Receive Ports - RX Gearbox Ports  --------------------
        RXGEARBOXSLIP                   =>      gnd,
        ------------- Receive Ports - RX Initialization and Reset Ports ------------
        GTRXRESET                       =>      GTRXRESET_in,
        RXOOBRESET                      =>      gnd,
        RXPCSRESET                      =>      RXPCSRESET_in,
        RXPMARESET                      =>      RXPMARESET_in,
        ------------------ Receive Ports - RX Margin Analysis ports ----------------
        RXLPMEN                         =>      gnd,
        ------------------- Receive Ports - RX OOB Signaling ports -----------------
        RXCOMSASDET                     =>      open,
        RXCOMWAKEDET                    =>      open,
        ------------------ Receive Ports - RX OOB Signaling ports  -----------------
        RXCOMINITDET                    =>      open,
        ------------------ Receive Ports - RX OOB signalling Ports -----------------
        RXELECIDLE                      =>      open,
        RXELECIDLEMODE                  =>      "11",
        ----------------- Receive Ports - RX Polarity Control Ports ----------------
        RXPOLARITY                      =>      RXPOLARITY_in,
        ---------------------- Receive Ports - RX gearbox ports --------------------
        RXSLIDE                         =>      RXSLIDE_in,
        ------------------- Receive Ports - RX8B/10B Decoder Ports -----------------
        RXCHARISCOMMA                   =>      open,
        RXCHARISK(7 downto 2)           =>      rxcharisk_float_i,
        RXCHARISK(1 downto 0)           =>      rx_charisk,
        ------------------ Receive Ports - Rx Channel Bonding Ports ----------------
        RXCHBONDI                       =>      "00000",
        -------------- Receive Ports -RX Initialization and Reset Ports ------------
        RXRESETDONE                     =>      RXRESETDONE_out,
        -------------------------------- Rx AFE Ports ------------------------------
        RXQPIEN                         =>      gnd,
        RXQPISENN                       =>      open,
        RXQPISENP                       =>      open,
        --------------------------- TX Buffer Bypass Ports -------------------------
        TXPHDLYTSTCLK                   =>      gnd,
        ------------------------ TX Configurable Driver Ports ----------------------
        TXPOSTCURSOR                    =>      "00000",
        TXPOSTCURSORINV                 =>      gnd,
        TXPRECURSOR                     =>      gnd_vec(4 downto 0),
        TXPRECURSORINV                  =>      gnd,
        TXQPIBIASEN                     =>      gnd,
        TXQPISTRONGPDOWN                =>      gnd,
        TXQPIWEAKPUP                    =>      gnd,
        --------------------- TX Initialization and Reset Ports --------------------
        CFGRESET                        =>      gnd,
        GTTXRESET                       =>      GTTXRESET_in,
        PCSRSVDOUT                      =>      open,
        TXUSERRDY                       =>      TXUSERRDY_in,
        ---------------------- Transceiver Reset Mode Operation --------------------
        GTRESETSEL                      =>      gnd,
        RESETOVRD                       =>      gnd,
        ---------------- Transmit Ports - 8b10b Encoder Control Ports --------------
        TXCHARDISPMODE                  =>      gnd_vec(7 downto 0),
        TXCHARDISPVAL                   =>      gnd_vec(7 downto 0),
        ------------------ Transmit Ports - FPGA TX Interface Ports ----------------
        TXUSRCLK                        =>      txusrclk,
        TXUSRCLK2                       =>      txusrclk,
        --------------------- Transmit Ports - PCI Express Ports -------------------
        TXELECIDLE                      =>      gnd,
        TXMARGIN                        =>      gnd_vec(2 downto 0),
        TXRATE                          =>      gnd_vec(2 downto 0),
        TXSWING                         =>      gnd,
        ------------------ Transmit Ports - Pattern Generator Ports ----------------
        TXPRBSFORCEERR                  =>      gnd,
        ------------------ Transmit Ports - TX Buffer Bypass Ports -----------------
        TXDLYBYPASS                     =>      vcc,
        TXDLYEN                         =>      gnd,
        TXDLYHOLD                       =>      gnd,
        TXDLYOVRDEN                     =>      gnd,
        TXDLYSRESET                     =>      TXDLYSRESET_in,
        TXDLYSRESETDONE                 =>      open,
        TXDLYUPDOWN                     =>      gnd,
        TXPHALIGN                       =>      vcc,
        TXPHALIGNDONE                   =>      open,
        TXPHALIGNEN                     =>      vcc,
        TXPHDLYPD                       =>      gnd,
        TXPHDLYRESET                    =>      gnd,
        TXPHINIT                        =>      gnd,
        TXPHINITDONE                    =>      open,
        TXPHOVRDEN                      =>      vcc,
        ---------------------- Transmit Ports - TX Buffer Ports --------------------
        TXBUFSTATUS                     =>      txbufstatus_i,
        --------------- Transmit Ports - TX Configurable Driver Ports --------------
        TXBUFDIFFCTRL                   =>      "100",
        TXDEEMPH                        =>      gnd,
        TXDIFFCTRL                      =>      "1000",
        TXDIFFPD                        =>      gnd,
        TXINHIBIT                       =>      gnd,
        TXMAINCURSOR                    =>      "0000000",
        TXPISOPD                        =>      gnd,
        ------------------ Transmit Ports - TX Data Path interface -----------------
        TXDATA                          =>      txdata_i,
        ---------------- Transmit Ports - TX Driver and OOB signaling --------------
        GTXTXN                          =>      TXN,
        GTXTXP                          =>      TXP,
        ----------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
        TXOUTCLK                        =>      tx_outclk,
        TXOUTCLKFABRIC                  =>      TXOUTCLKFABRIC_out,
        TXOUTCLKPCS                     =>      TXOUTCLKPCS_out,
        TXOUTCLKSEL                     =>      "011",
        TXRATEDONE                      =>      open,
        --------------------- Transmit Ports - TX Gearbox Ports --------------------
        TXCHARISK(7 downto 2)           =>      gnd_vec(5 downto 0),
        TXCHARISK(1 downto 0)           =>      tx_charisk,
        TXGEARBOXREADY                  =>      open,
        TXHEADER                        =>      gnd_vec(2 downto 0),
        TXSEQUENCE                      =>      gnd_vec(6 downto 0),
        TXSTARTSEQ                      =>      gnd,
        ------------- Transmit Ports - TX Initialization and Reset Ports -----------
        TXPCSRESET                      =>      TXPCSRESET_in,
        TXPMARESET                      =>      TXPMARESET_in,
        TXRESETDONE                     =>      TXRESETDONE_out,
        ------------------ Transmit Ports - TX OOB signalling Ports ----------------
        TXCOMFINISH                     =>      open,
        TXCOMINIT                       =>      gnd,
        TXCOMSAS                        =>      gnd,
        TXCOMWAKE                       =>      gnd,
        TXPDELECIDLEMODE                =>      gnd,
        ----------------- Transmit Ports - TX Polarity Control Ports ---------------
        TXPOLARITY                      =>      TXPOLARITY_in,
        --------------- Transmit Ports - TX Receiver Detection Ports  --------------
        TXDETECTRX                      =>      gnd,
        ------------------ Transmit Ports - TX8b/10b Encoder Ports -----------------
        TX8B10BBYPASS                   =>      gnd_vec(7 downto 0),
        ------------------ Transmit Ports - pattern Generator Ports ----------------
        TXPRBSSEL                       =>      gnd_vec(2 downto 0),
        ----------------------- Tx Configurable Driver  Ports ----------------------
        TXQPISENN                       =>      open,
        TXQPISENP                       =>      open

    );

  refclk_select_1: 
  if REFCLKSEL = '1' generate
    REFCLK0 <= '0';
    refclk1_ibufds_i : IBUFDS_GTE2
      port map
      (
        I     => REFCLK1P,
        IB    => REFCLK1N,
        CEB   => gnd,
        O     => REFCLK1,
        ODIV2 => open);
    CPLLREFCLKSEL_in <= "010"; -- MGTREFCLK1
  end generate;

  refclk_select_0: 
  if REFCLKSEL = '0' generate
    refclk0_ibufds_i : IBUFDS_GTE2
      port map
      (
        I	=> REFCLK0P,
        IB      => REFCLK0N,
        CEB     => gnd,
        O	=> REFCLK0,
        ODIV2   => open);
    REFCLK1 <= '0';
    CPLLREFCLKSEL_in <= "001"; -- MGTREFCLK0
  end generate;

  i_dc_fifo : FIFO36E1
    generic map (
      ALMOST_EMPTY_OFFSET => X"0080",
      ALMOST_FULL_OFFSET => X"0080",
      DATA_WIDTH => 36,
      DO_REG => 1,
      EN_SYN => FALSE,
      FIFO_MODE => "FIFO36",
      FIRST_WORD_FALL_THROUGH => FALSE,
      INIT => X"000000000",
      SIM_DEVICE => "7SERIES",
      SRVAL => X"000000000")
    port map (
      DO => fifo_do,
      DOP => fifo_dop,
      ECCPARITY => open,
      ALMOSTEMPTY => open,
      ALMOSTFULL => open,
      DBITERR => open,
      SBITERR => open,
      EMPTY => open,
      FULL => open,
      RDCOUNT => open,
      RDERR => open,
      WRCOUNT => open,
      WRERR => open,
      RDCLK => event_clk,
      RDEN => fifo_rden,
      REGCE => vcc,
      RST => fifo_rst,
      RSTREG => gnd,
      WRCLK => rxusrclk,
      WREN => fifo_wren,
      DI => fifo_di,
      DIP => fifo_dip,
      INJECTDBITERR => gnd,
      INJECTSBITERR => gnd);
  
  i_txfifo : FIFO18E1
    generic map (
      ALMOST_EMPTY_OFFSET => X"0080",
      ALMOST_FULL_OFFSET => X"0080",
      DATA_WIDTH => 9,
      DO_REG => 1,
      EN_SYN => FALSE,
      FIFO_MODE => "FIFO18",
      FIRST_WORD_FALL_THROUGH => FALSE,
      INIT => X"000000000",
      SIM_DEVICE => "7SERIES",
      SRVAL => X"000000000")
    port map (
      DO => tx_fifo_do,
      DOP => tx_fifo_dop,
      ALMOSTEMPTY => open,
      ALMOSTFULL => open,
      EMPTY => tx_fifo_empty,
      FULL => open,
      RDCOUNT => open,
      RDERR => tx_fifo_rderr,
      WRCOUNT => open,
      WRERR => open,
      RDCLK => txusrclk,
      RDEN => tx_fifo_rden,
      REGCE => vcc,
      RST => tx_fifo_rst,
      RSTREG => gnd,
      WRCLK => refclk,
      WREN => tx_fifo_wren,
      DI => tx_fifo_di,
      DIP => tx_fifo_dip);
  
  vcc <= '1';
  gnd <= '0';
  gnd_vec <= (others => '0');
  tied_to_ground_i                    <= '0';
  tied_to_ground_vec_i(63 downto 0)   <= (others => '0');
  tied_to_vcc_i                       <= '1';

  RXEQMIX <= "01";
  RXDFELPMRESET_in <= reset;
  RXDLYEN_in <= '0';
  RXDLYSRESET_in <= reset;
  RXPCSRESET_in <= reset;
  RXPHALIGN_in <= '0';
  RXPHALIGNEN_in <= '0';
  RXPHDLYRESET_in <= reset;
  RXPMARESET_in <= reset;
  RXPOLARITY_in <= RX_POLARITY;
  RXSLIDE_in <= '0';
  TXDLYEN_in <= '0';
  TXDLYSRESET_in <= reset;
  TXPCSRESET_in <= '0';
  TXPHALIGN_in <= '0';
  TXPHALIGNEN_in <= '0';
  TXPHDLYRESET_in <= '0';
  TXPHINIT_in <= '0';
  TXPMARESET_in <= '0';
  TXPOLARITY_in <= TX_POLARITY;
  
  i_bufg0: BUFG
    port map (
      O => rxusrclk,
      I => RXOUTCLK_out);

  i_bufg1: BUFG
    port map (
      O => txusrclk,
      I => tx_outclk);

  recclk_out <= rxusrclk;
  REFCLK_OUT <= refclk;
  refclk <= txusrclk;
  
  rx_powerdown <= '0';
  tx_powerdown <= '0';

  fifo_di(63 downto 16) <= (others => '0');
  fifo_di(15 downto 0) <= rx_data;
  fifo_dip(7 downto 4) <= (others => '0');
  fifo_dip(2) <= '0';
  fifo_dip(1 downto 0) <= rx_charisk;

  rx_beacon <= rx_beacon_i;
  rx_int_beacon <= rx_int_beacon_i;
  rx_int_beacon_i <= fifo_dop(3);
  fifo_dip(3) <= rx_beacon_i;
  
  receive_error_detect : process (rxusrclk, rx_data, rx_charisk,
				  rx_disperr, rx_notintable)
    variable beacon_cnt : std_logic_vector(2 downto 0) := "000";
    variable cnt : std_logic_vector(12 downto 0);
  begin
    if rising_edge(rxusrclk) then
      rx_error <= '0';
      if (rx_charisk(0) = '1' and rx_data(7) = '1') or
        rx_disperr /= "00" or rx_notintable /= "00" then
        rx_error <= '1';
      end if;
      if beacon_cnt(beacon_cnt'high) = '1' then
        beacon_cnt := beacon_cnt - 1;
      end if;
      if link_ok = '1' and rx_charisk(1) = '0' and rx_data(15 downto 8) = C_EVENT_BEACON then
        beacon_cnt := "111";
      end if;
      rx_beacon_i <= beacon_cnt(beacon_cnt'high);
      if dc_mode = '0' then
        rx_beacon_i <= cnt(cnt'high);
      end if;
      if cnt(cnt'high) = '1' then
        cnt(cnt'high) := '0';
      end if;
      cnt := cnt + 1;
    end if;
  end process;

  link_ok_detection : process (refclk, link_ok, reset, rx_error_i)
    variable link_ok_delay : std_logic_vector(19 downto 0) := (others => '0');
  begin
    rx_link_ok <= rx_link_ok_i;
    rx_link_ok_i <= link_ok_delay(link_ok_delay'high);
    if rising_edge(refclk) then
      if link_ok_delay(link_ok_delay'high) = '0' then
        link_ok_delay := link_ok_delay + 1;
      end if;
      if reset = '1' or link_ok = '0' or rx_error_i = '1' then
        link_ok_delay := (others => '0');
      end if;
    end if;
  end process;

  link_status_testing : process (refclk, reset, rx_charisk, link_ok,
				 rx_disperr, CPLLLOCK_out)
    variable prescaler : std_logic_vector(14 downto 0);
    variable count : std_logic_vector(3 downto 0);
    variable rx_error_sync : std_logic;
    variable rx_error_sync_1 : std_logic;
    variable loss_lock : std_logic;
    variable rx_error_count : std_logic_vector(5 downto 0);
    variable reset_sync : std_logic_vector(1 downto 0);
  begin
    TRIG0(58 downto 53) <= rx_error_count;
    TRIG0(59) <= loss_lock;
    TRIG0(60) <= rx_error_sync;
    TRIG0(75 downto 61) <= prescaler;
    TRIG0(79 downto 76) <= count;
    
    if rising_edge(refclk) then
      rxcdrreset <= '0';
      if GTRXRESET_in = '0' then
        if prescaler(prescaler'high) = '1' then
          link_ok <= '0';
          if count = "0000" then
            link_ok <= '1';
          end if;
      
          if count = "1111" then
            rxcdrreset <= '1';
          end if;

          if count(count'high) = '1' then
            rx_error_count := "011111";
          end if;
          
          if count /= "0000" then
            count := count - 1;
          end if;
        end if;

        if count = "0000" then
          if loss_lock = '1' then
            count := "1111";
          end if;
        end if;

	loss_lock := rx_error_count(5);

        if rx_error_sync = '1' then
          if rx_error_count(5) = '0' then
            rx_error_count := rx_error_count - 1;
          end if;
        else
          if prescaler(prescaler'high) = '1' and
            (rx_error_count(5) = '1' or rx_error_count(4) = '0') then
            rx_error_count := rx_error_count + 1;
          end if;
        end if;
	
        if prescaler(prescaler'high) = '1' then
          prescaler := "011111111111111";
        else
          prescaler := prescaler - 1;
        end if;
      end if;

      rx_error_i <= rx_error_sync_1;
      rx_error_sync := rx_error_sync_1;
      rx_error_sync_1 := rx_error;
      
      if reset_sync(0) = '1' then
        count := "1111";
      end if;

      -- Synchronize asynchronous resets
      reset_sync(0) := reset_sync(1);
      reset_sync(1) := '0';
      if reset = '1' or CPLLLOCK_out = '0' then
        reset_sync(1) := '1';
      end if;
    end if;
  end process;

  reg_dbus_data : process (event_clk, rx_link_ok_i, rx_data, databuf_rxd_i, databuf_rx_k_i)
    variable even : std_logic;
  begin
    databuf_rxd <= databuf_rxd_i;
    databuf_rx_k <= databuf_rx_k_i;
    if rising_edge(event_clk) then
      if databuf_rx_mode = '0' or even = '0' then
	dbus_rxd <= fifo_do(7 downto 0);
      end if;
      if databuf_rx_mode = '1' then
	if even = '1' then
	  databuf_rxd_i <= fifo_do(7 downto 0);
	  databuf_rx_k_i <= fifo_dop(0);
	end if;
      else
	databuf_rxd_i <= (others => '0');
	databuf_rx_k_i <= '0';
      end if;

      databuf_rx_ena <= even;
      
      if rx_link_ok_i = '0' then
	databuf_rxd_i <= (others => '0');
	databuf_rx_k_i <= '0';
	dbus_rxd <= (others => '0');
      end if;

      even := not even;
      event_rxd <= fifo_do(15 downto 8);
      if rx_link_ok_i = '0' or fifo_dop(1) = '1' or
	reset = '1' then
	event_rxd <= (others => '0');
	even := '0';
      end if;
    end if;
  end process;

  rx_data_align_detect : process (rxusrclk, reset, rx_charisk, rx_data,
				  rx_clear_viol)
  begin
    if reset = '1' or rx_clear_viol = '1' then
      align_error <= '0';
    elsif rising_edge(rxusrclk) then
      align_error <= '0';
      if rx_charisk(0) = '1' and rx_data(7) = '1' then
	align_error <= '1';
      end if;
    end if;
  end process;

  violation_flag : process (sys_clk, rx_clear_viol, rx_link_ok_i, rx_vio_usrclk)
    variable vio : std_logic;
  begin
    if rising_edge(sys_clk) then
      if rx_clear_viol = '1' then
        rx_violation <= '0';
      end if;
      if vio = '1' or rx_link_ok_i = '0' then
        rx_violation <= '1';
      end if;
      vio := rx_vio_usrclk;
    end if;
  end process;
  
  violation_detect : process (rxusrclk, rx_clear_viol,
			      rx_disperr, rx_notintable, link_ok)
    variable clrvio : std_logic;
  begin
    if rising_edge(rxusrclk) then
      if rx_disperr /= "00" or
        rx_notintable /= "00" then
	rx_vio_usrclk <= '1';
      elsif clrvio = '1' then
        rx_vio_usrclk <= '0';
      end if;

      clrvio := rx_clear_viol;
    end if;
  end process;

  TRIG0(15 downto 0) <= rx_data;
  TRIG0(17 downto 16) <= rx_charisk;
  TRIG0(19 downto 18) <= rx_disperr;
  TRIG0(21 downto 20) <= "00";
  TRIG0(23 downto 22) <= rx_notintable;
  TRIG0(24) <= link_ok;
  TRIG0(25) <= CPLLRESET_in;
  TRIG0(26) <= GTTXRESET_in;
  TRIG0(27) <= TXUSERRDY_in;
  TRIG0(28) <= GTRXRESET_in;
  TRIG0(29) <= RXUSERRDY_in;
  TRIG0(30) <= '0';
  TRIG0(31) <= '0';
  TRIG0(47 downto 32) <= tx_data;
  TRIG0(49 downto 48) <= tx_charisk;
  TRIG0(50) <= rx_error;
  TRIG0(51) <= rxcdrreset;
  TRIG0(52) <= align_error;
  TRIG0(87 downto 80) <= databuf_rxd_i;
  TRIG0(88) <= databuf_rx_k_i;
  TRIG0(89) <= RXCDRLOCK_out;
  TRIG0(90) <= RXPCSRESET_in;
  TRIG0(91) <= RXPMARESET_in;
  TRIG0(92) <= RXRESETDONE_out;
  TRIG0(116 downto 93) <= (others => '0');
  TRIG0(117) <= databuf_tx_mode;
  TRIG0(119) <= databuf_tx_k;
  TRIG0(127 downto 120) <= databuf_txd;
  TRIG0(143 downto 128) <= fifo_do(15 downto 0);
  TRIG0(147 downto 144) <= fifo_dop(3 downto 0);
  TRIG0(148) <= fifo_rden;
  TRIG0(156 downto 149) <= tx_fifo_do(7 downto 0);
  TRIG0(164 downto 157) <= tx_fifo_di(7 downto 0);
  TRIG0(165) <= tx_fifo_wren;
  TRIG0(166) <= tx_fifo_rden;
  TRIG0(167) <= tx_fifo_empty;
  TRIG0(168) <= tx_event_ena_i;
  TRIG0(250 downto 170) <= (others => '0');

  process (rxusrclk)
    variable toggle : std_logic := '0';
  begin
    TRIG0(169) <= toggle;
    if rising_edge(rxusrclk) then
      toggle := not toggle;
    end if;
  end process;
  
  rx_data <= rxdata_i(15 downto 0);
  txdata_i <= (tied_to_ground_vec_i(47 downto 0) & tx_data);

  -- Scalers for clocks for debugging purposes to see which clocks
  -- are running using the ILA core
  
  process (refclk, reset)
    variable cnt : std_logic_vector(2 downto 0);
  begin
    TRIG0(255) <= cnt(cnt'high);
    if rising_edge(refclk) then
      cnt := cnt + 1;
      if reset = '1' then
        cnt := (others => '0');
      end if;
    end if;
  end process;
  
  process (sys_clk, reset)
    variable cnt : std_logic_vector(2 downto 0);
  begin
    TRIG0(254) <= cnt(cnt'high);
    if rising_edge(sys_clk) then
      cnt := cnt + 1;
      if reset = '1' then
        cnt := (others => '0');
      end if;
    end if;
  end process;
  
  process (event_clk, reset)
    variable cnt : std_logic_vector(2 downto 0);
  begin
    TRIG0(253) <= cnt(cnt'high);
    if rising_edge(event_clk) then
      cnt := cnt + 1;
      if reset = '1' then
        cnt := (others => '0');
      end if;
    end if;
  end process;
  
  process (rxusrclk, reset)
    variable cnt : std_logic_vector(2 downto 0);
  begin
    TRIG0(252) <= cnt(cnt'high);
    if rising_edge(rxusrclk) then
      cnt := cnt + 1;
      if reset = '1' then
        cnt := (others => '0');
      end if;
    end if;
  end process;
  
  process (txusrclk, reset)
    variable cnt : std_logic_vector(2 downto 0);
  begin
    TRIG0(251) <= cnt(cnt'high);
    if rising_edge(txusrclk) then
      cnt := cnt + 1;
      if reset = '1' then
        cnt := (others => '0');
      end if;
    end if;
  end process;
  
  cpll_reset: process (sys_clk, reset)
    variable cnt : std_logic_vector(25 downto 0) := (others => '1');
  begin
    if rising_edge(sys_clk) then
      CPLLRESET_in <= cnt(cnt'high);
      if cnt(cnt'high) = '1' then
        cnt := cnt - 1;
        GTTXRESET_in <= '1';
        TXUSERRDY_in <= '0';
      end if;
      if reset = '1' then
        cnt := (others => '1');
      end if;
      if CPLLLOCK_out = '1' then
        GTTXRESET_in <= '0';
        TXUSERRDY_in <= '1';
      end if;
    end if;
  end process;
  
  rx_resetting: process (refclk, rxcdrreset)
    variable cnt : std_logic_vector(25 downto 0) := (others => '1');
  begin
    if rising_edge(refclk) then
      GTRXRESET_in <= cnt(cnt'high);
      RXUSERRDY_in <= not cnt(cnt'high);
      if cnt(cnt'high) = '1' then
        cnt := cnt - 1;
      end if;
      if rxcdrreset = '1' then
        cnt := (others => '1');
      end if;
    end if;
  end process;

  transmit_data : process (txusrclk, tx_fifo_do, tx_fifo_empty, dbus_txd,
                           databuf_txd, databuf_tx_k, databuf_tx_mode, dc_mode,
                           reset)
    variable even       : std_logic_vector(1 downto 0) := "00";
    variable beacon_cnt : std_logic_vector(3 downto 0) := "0000"; 
    variable fifo_pend  : std_logic;
  begin
    tx_event_ena <= tx_event_ena_i;
    tx_event_ena_i <= '1';
    tx_fifo_rden <= '1';
    if beacon_cnt(1 downto 0) = "10" and dc_mode = '1' then
      tx_event_ena_i <= '0';
      if tx_fifo_empty = '0' then
        tx_fifo_rden <= '0';
      end if;
    end if;
    if rising_edge(txusrclk) then
      tx_charisk <= "00";
      tx_data(15 downto 8) <= (others => '0');
      tx_beacon <= beacon_cnt(1);
      if beacon_cnt(1 downto 0) = "10" and dc_mode = '1' then
	tx_data(15 downto 8) <= C_EVENT_BEACON; -- Beacon event
      elsif tx_fifo_rderr = '0' then
        tx_data(15 downto 8) <= tx_fifo_do(7 downto 0);
        fifo_pend := '0';
      elsif even = "00" then
	tx_charisk <= "10";
	tx_data(15 downto 8) <= X"BC"; -- K28.5 character
      end if;

      if tx_fifo_empty = '0' then
        fifo_pend := '1';
      end if;

      tx_data(7 downto 0) <= dbus_txd;
      if even(0) = '0' and databuf_tx_mode = '1' then
	tx_data(7 downto 0) <= databuf_txd;
	tx_charisk(0) <= databuf_tx_k;
      end if;
      databuf_tx_ena <= even(0);
      TRIG0(118) <= even(0);
      even := even + 1;
      beacon_cnt := rx_beacon_i & beacon_cnt(beacon_cnt'high downto 1);
      if reset = '1' then
        fifo_pend := '0';
      end if;
    end if;
  end process;

  -- Read and write enables are used to adjust the coarse delay
  -- These can cause data packet corruption and missing events -
  -- thus this method is used only during link training
  
  fifo_read_enable : process (event_clk, delay_inc)
    variable sr_delay_trig : std_logic_vector(2 downto 0) := "000";
  begin
    if rising_edge(event_clk) then
      fifo_rden <= '1';
      if sr_delay_trig(1 downto 0) = "10" then
        fifo_rden <= '0';
      end if;
      sr_delay_trig := delay_inc & sr_delay_trig(2 downto 1);
    end if;
  end process;
  
  fifo_write_enable : process (rxusrclk, delay_dec)
    variable sr_delay_trig : std_logic_vector(2 downto 0) := "000";
  begin
    if rising_edge(rxusrclk) then
      fifo_wren <= '1';
      if sr_delay_trig(1 downto 0) = "10" then
        fifo_wren <= '0';
      end if;
      sr_delay_trig := delay_dec & sr_delay_trig(2 downto 1);
    end if;
  end process;

  fifo_rst <= not link_ok;

  tx_fifo_writing : process (refclk, event_txd)
  begin
    tx_fifo_di <= (others => '0');
    tx_fifo_di(7 downto 0) <= event_txd;
    tx_fifo_wren <= '0';
    if event_txd /= X"00" then
      tx_fifo_wren <= '1';
    end if;
  end process;
  
  tx_fifo_dip <= (others => '0');
  tx_fifo_rst <= reset;
  
  drpclk <= txusrclk;

  process (drpclk, reset, txbufstatus_i, TXUSERRDY_in)
    type state is (init, init_delay, acq_bufstate, deldec, delinc, locked);
    variable ph_state : state;
    variable phase       : std_logic_vector(6 downto 0);
    variable cnt      : std_logic_vector(19 downto 0);
    variable halffull : std_logic;
  begin
    if rising_edge(drpclk) then
      if (ph_state = acq_bufstate) or
        (ph_state = delinc) or
        (ph_state = deldec) then
        if txbufstatus_i(0) = '1' then
          halffull := '1';
        end if;
      end if;

      phase_acc_en <= '0';
      if cnt(cnt'high) = '1' then
        case ph_state is
          when init =>
            if reset = '0' then
              ph_state := init_delay;
            end if;
          when init_delay =>
            halffull := '0';
            ph_state := acq_bufstate;
          when acq_bufstate =>
            if halffull = '0' then
              ph_state := delinc;
            else
              ph_state := deldec;
            end if;
            halffull := '0';
          when deldec =>
            if halffull = '1' then
              phase := phase - 1;
            else
              ph_state := delinc;
            end if;
            halffull := '0';
            phase_acc_en <= '1';
          when delinc =>
            if halffull = '0' then
              phase := phase + 1;
            else
              ph_state := locked;
            end if;
            halffull := '0';
            phase_acc_en <= '1';
          when others =>
        end case;
        phase_acc <= phase;
        cnt := (others => '0');
      else
        cnt := cnt + 1;
      end if;
      if reset = '1' or TXUSERRDY_in = '0' then
        ph_state := init;
        phase := (others => '0');
        cnt := (others => '0');
      end if;
    end if;
  end process;
  
  process (drpclk, phase_acc, phase_acc_en, reset)
    type state is (idle, a64_0, a64_1, a64_2, a9f_0, a9f_1, a9f_2, a9f_3, a9f_4, a9f_5);
    variable drp_state, next_state : state;
    variable rdy_wait : std_logic;
  begin
    if rising_edge(drpclk) then
      rdy_wait := '0';
      case drp_state is
        when a64_0 =>
          drpaddr <= '0' & X"64";
          drpdi <= X"00" & '0' & phase_acc;
          drpen <= '0';
          drpwe <= '0';
          next_state := a64_1;
        when a64_1 =>
          drpaddr <= '0' & X"64";
          drpdi <= X"00" & '0' & phase_acc;
          drpen <= '1';
          drpwe <= '1';
          next_state := a64_2;
        when a64_2 =>
          drpaddr <= '0' & X"64";
          drpdi <= X"00" & '0' & phase_acc;
          drpen <= '0';
          drpwe <= '0';
          next_state := a9f_0;
          rdy_wait := '1';
        when a9f_0 =>
          drpaddr <= '0' & X"9F";
          drpdi <= X"0035";
          drpen <= '0';
          drpwe <= '0';
          next_state := a9f_1;
        when a9f_1 =>
          drpaddr <= '0' & X"9F";
          drpdi <= X"0035";
          drpen <= '1';
          drpwe <= '1';
          next_state := a9f_2;
        when a9f_2 =>
          drpaddr <= '0' & X"9F";
          drpdi <= X"0035";
          drpen <= '0';
          drpwe <= '0';
          rdy_wait := '1';
          next_state := a9f_3;
        when a9f_3 =>
          drpaddr <= '0' & X"9F";
          drpdi <= X"0034";
          drpen <= '0';
          drpwe <= '0';
          next_state := a9f_4;
        when a9f_4 =>
          drpaddr <= '0' & X"9F";
          drpdi <= X"0034";
          drpen <= '1';
          drpwe <= '1';
          next_state := a9f_5;
        when a9f_5 =>
          drpaddr <= '0' & X"9F";
          drpdi <= X"0034";
          drpen <= '0';
          drpwe <= '0';
          rdy_wait := '1';
          next_state := idle;
        when others =>
          drpaddr <= '0' & X"64";
          drpdi <= X"00" & '0' & phase_acc;
          drpen <= '0';
          drpwe <= '0';
          next_state := idle;
          rdy_wait := '0';
      end case;
      if rdy_wait = '0' or drprdy = '1' then
        if drp_state = idle and phase_acc_en = '1' then
          next_state := a64_0;
        end if;
        drp_state := next_state;
      end if;
      if reset = '1' then
        drp_state := idle;
        rdy_wait := '0';
      end if;
    end if;
  end process;

end structure;
