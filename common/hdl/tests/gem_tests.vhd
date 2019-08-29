------------------------------------------------------------------------------------------------------------------------------------------------------
-- Company: TAMU
-- Engineer: Evaldas Juska (evaldas.juska@cern.ch, evka85@gmail.com)
-- 
-- Create Date:    20:38:00 2016-08-30
-- Module Name:    GEM_TESTS
-- Description:    This module is the entry point for hardware tests e.g. fiber loopback testing with generated data 
------------------------------------------------------------------------------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gem_pkg.all;
use work.ttc_pkg.all;
use work.ipbus.all;
use work.registers.all;

entity gem_tests is
    generic(
        g_NUM_GBT_LINKS     : integer;
        g_NUM_OF_OHs        : integer;
        g_GEM_STATION       : integer
    );
    port(
        -- reset
        reset_i                     : in  std_logic;
        
        -- TTC
        ttc_clk_i                   : in  t_ttc_clks;        
        ttc_cmds_i                  : in  t_ttc_cmds;
        
        -- Test control
        loopback_gbt_test_en_i      : in std_logic;
        
        -- GBT links
        gbt_link_ready_i            : in  std_logic_vector(g_NUM_GBT_LINKS - 1 downto 0);
        gbt_tx_data_arr_o           : out t_gbt_frame_array(g_NUM_GBT_LINKS - 1 downto 0);
        gbt_rx_data_arr_i           : in  t_gbt_frame_array(g_NUM_GBT_LINKS - 1 downto 0);
        
        -- VFAT3 daq input for channel monitoring
        vfat3_daq_links_arr_i       : in t_oh_vfat_daq_link_arr(g_NUM_OF_OHs - 1 downto 0);
        
        -- IPbus
        ipb_reset_i                 : in  std_logic;
        ipb_clk_i                   : in  std_logic;
        ipb_miso_o                  : out ipb_rbus;
        ipb_mosi_i                  : in  ipb_wbus        
    );
end gem_tests;

architecture Behavioral of gem_tests is

    -- reset
    signal reset_global                 : std_logic;
    signal reset_local                  : std_logic;
    signal reset                        : std_logic;

    -- control
    signal gbt_loop_through_oh          : std_logic;
    
    -- gbt loopback status
    signal gbt_loop_sync_done_arr       : std_logic_vector(g_NUM_GBT_LINKS - 1 downto 0);
    signal gbt_loop_mega_word_cnt_arr   : t_std32_array(g_NUM_GBT_LINKS - 1 downto 0);
    signal gbt_loop_error_cnt_arr       : t_std32_array(g_NUM_GBT_LINKS - 1 downto 0);
    
    -- VFAT3 DAQ monitor
    signal vfat_daq_links24             : t_vfat_daq_link_arr(23 downto 0);
    signal vfat_daqmon_reset            : std_logic;
    signal vfat_daqmon_enable           : std_logic;
    signal vfat_daqmon_oh_select        : std_logic_vector(3 downto 0);
    signal vfat_daqmon_chan_select      : std_logic_vector(6 downto 0);
    signal vfat_daqmon_chan_global_or   : std_logic;
    signal vfat_daqmon_good_evt_cnt_arr : t_std16_array(23 downto 0); 
    signal vfat_daqmon_chan_fire_cnt_arr: t_std16_array(23 downto 0); 
    
    ------ Register signals begin (this section is generated by <gem_amc_repo_root>/scripts/generate_registers.py -- do not edit)
    signal regs_read_arr        : t_std32_array(REG_GEM_TESTS_NUM_REGS - 1 downto 0);
    signal regs_write_arr       : t_std32_array(REG_GEM_TESTS_NUM_REGS - 1 downto 0);
    signal regs_addresses       : t_std32_array(REG_GEM_TESTS_NUM_REGS - 1 downto 0);
    signal regs_defaults        : t_std32_array(REG_GEM_TESTS_NUM_REGS - 1 downto 0) := (others => (others => '0'));
    signal regs_read_pulse_arr  : std_logic_vector(REG_GEM_TESTS_NUM_REGS - 1 downto 0);
    signal regs_write_pulse_arr : std_logic_vector(REG_GEM_TESTS_NUM_REGS - 1 downto 0);
    signal regs_read_ready_arr  : std_logic_vector(REG_GEM_TESTS_NUM_REGS - 1 downto 0) := (others => '1');
    signal regs_write_done_arr  : std_logic_vector(REG_GEM_TESTS_NUM_REGS - 1 downto 0) := (others => '1');
    signal regs_writable_arr    : std_logic_vector(REG_GEM_TESTS_NUM_REGS - 1 downto 0) := (others => '0');
    ------ Register signals end ----------------------------------------------    

begin

    --== Resets ==--
    
    i_reset_sync : entity work.synchronizer
        generic map(
            N_STAGES => 3
        )
        port map(
            async_i => reset_i,
            clk_i   => ttc_clk_i.clk_40,
            sync_o  => reset_global
        );

    reset <= reset_global or reset_local;
    
    --== GBT loopback test ==--
    
    g_use_gbtx : if (g_GEM_STATION = 1) or (g_GEM_STATION = 2) generate
        g_gbt_loopback_tests : for i in 0 to g_NUM_GBT_LINKS - 1 generate
        
            i_gbt_loopback_test_single : entity work.gbt_loopback_test
                port map(
                    reset_i          => reset or not loopback_gbt_test_en_i,
                    gbt_clk_i        => ttc_clk_i.clk_40,
                    gbt_link_ready_i => gbt_link_ready_i(i),
                    gbt_tx_data_o    => gbt_tx_data_arr_o(i),
                    gbt_rx_data_i    => gbt_rx_data_arr_i(i),
                    oh_in_the_loop_i => gbt_loop_through_oh,
                    link_sync_done_o => gbt_loop_sync_done_arr(i),
                    mega_word_cnt_o  => gbt_loop_mega_word_cnt_arr(i),
                    error_cnt_o      => gbt_loop_error_cnt_arr(i)
                );
        
        end generate;
    end generate;

    --== VFAT3 DAQ monitor ==--
    
    vfat_daq_links24 <= vfat3_daq_links_arr_i(to_integer(unsigned(vfat_daqmon_oh_select)));
    
    g_vfat3_daq_monitors : for i in 0 to 23 generate
        
        i_vfat3_daq_monitor : entity work.vfat3_daq_monitor
            port map(
                reset_i           => reset or vfat_daqmon_reset,
                enable_i          => vfat_daqmon_enable,
                ttc_clk_i         => ttc_clk_i,
                data_en_i         => vfat_daq_links24(i).data_en,
                data_i            => vfat_daq_links24(i).data,
                event_done_i      => vfat_daq_links24(i).event_done,
                crc_error_i       => vfat_daq_links24(i).crc_error,
                chan_global_or_i  => vfat_daqmon_chan_global_or,
                chan_single_idx_i => vfat_daqmon_chan_select,
                cnt_good_events_o => vfat_daqmon_good_evt_cnt_arr(i),
                cnt_chan_fired_o  => vfat_daqmon_chan_fire_cnt_arr(i)
            );
        
    end generate; 
    
    --===============================================================================================
    -- this section is generated by <gem_amc_repo_root>/scripts/generate_registers.py (do not edit) 
    --==== Registers begin ==========================================================================

    -- IPbus slave instanciation
    ipbus_slave_inst : entity work.ipbus_slave
        generic map(
           g_NUM_REGS             => REG_GEM_TESTS_NUM_REGS,
           g_ADDR_HIGH_BIT        => REG_GEM_TESTS_ADDRESS_MSB,
           g_ADDR_LOW_BIT         => REG_GEM_TESTS_ADDRESS_LSB,
           g_USE_INDIVIDUAL_ADDRS => true
       )
       port map(
           ipb_reset_i            => ipb_reset_i,
           ipb_clk_i              => ipb_clk_i,
           ipb_mosi_i             => ipb_mosi_i,
           ipb_miso_o             => ipb_miso_o,
           usr_clk_i              => ttc_clk_i.clk_40,
           regs_read_arr_i        => regs_read_arr,
           regs_write_arr_o       => regs_write_arr,
           read_pulse_arr_o       => regs_read_pulse_arr,
           write_pulse_arr_o      => regs_write_pulse_arr,
           regs_read_ready_arr_i  => regs_read_ready_arr,
           regs_write_done_arr_i  => regs_write_done_arr,
           individual_addrs_arr_i => regs_addresses,
           regs_defaults_arr_i    => regs_defaults,
           writable_regs_i        => regs_writable_arr
      );

    -- Addresses
    regs_addresses(0)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"0000";
    regs_addresses(1)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1000";
    regs_addresses(2)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1010";
    regs_addresses(3)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1011";
    regs_addresses(4)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1012";
    regs_addresses(5)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1020";
    regs_addresses(6)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1021";
    regs_addresses(7)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1022";
    regs_addresses(8)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1030";
    regs_addresses(9)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1031";
    regs_addresses(10)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1032";
    regs_addresses(11)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1040";
    regs_addresses(12)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1041";
    regs_addresses(13)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1042";
    regs_addresses(14)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1050";
    regs_addresses(15)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1051";
    regs_addresses(16)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1052";
    regs_addresses(17)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1060";
    regs_addresses(18)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1061";
    regs_addresses(19)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1062";
    regs_addresses(20)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1070";
    regs_addresses(21)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1071";
    regs_addresses(22)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1072";
    regs_addresses(23)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1080";
    regs_addresses(24)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1081";
    regs_addresses(25)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1082";
    regs_addresses(26)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1090";
    regs_addresses(27)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1091";
    regs_addresses(28)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1092";
    regs_addresses(29)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10a0";
    regs_addresses(30)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10a1";
    regs_addresses(31)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10a2";
    regs_addresses(32)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10b0";
    regs_addresses(33)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10b1";
    regs_addresses(34)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10b2";
    regs_addresses(35)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10c0";
    regs_addresses(36)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10c1";
    regs_addresses(37)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10c2";
    regs_addresses(38)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10d0";
    regs_addresses(39)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10d1";
    regs_addresses(40)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10d2";
    regs_addresses(41)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10e0";
    regs_addresses(42)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10e1";
    regs_addresses(43)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10e2";
    regs_addresses(44)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10f0";
    regs_addresses(45)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10f1";
    regs_addresses(46)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"10f2";
    regs_addresses(47)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1100";
    regs_addresses(48)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1101";
    regs_addresses(49)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1102";
    regs_addresses(50)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1110";
    regs_addresses(51)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1111";
    regs_addresses(52)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1112";
    regs_addresses(53)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1120";
    regs_addresses(54)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1121";
    regs_addresses(55)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1122";
    regs_addresses(56)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1130";
    regs_addresses(57)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1131";
    regs_addresses(58)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1132";
    regs_addresses(59)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1140";
    regs_addresses(60)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1141";
    regs_addresses(61)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1142";
    regs_addresses(62)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1150";
    regs_addresses(63)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1151";
    regs_addresses(64)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1152";
    regs_addresses(65)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1160";
    regs_addresses(66)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1161";
    regs_addresses(67)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1162";
    regs_addresses(68)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1170";
    regs_addresses(69)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1171";
    regs_addresses(70)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1172";
    regs_addresses(71)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1180";
    regs_addresses(72)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1181";
    regs_addresses(73)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"1182";
    regs_addresses(74)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2000";
    regs_addresses(75)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2001";
    regs_addresses(76)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2010";
    regs_addresses(77)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2020";
    regs_addresses(78)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2030";
    regs_addresses(79)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2040";
    regs_addresses(80)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2050";
    regs_addresses(81)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2060";
    regs_addresses(82)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2070";
    regs_addresses(83)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2080";
    regs_addresses(84)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2090";
    regs_addresses(85)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"20a0";
    regs_addresses(86)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"20b0";
    regs_addresses(87)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"20c0";
    regs_addresses(88)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"20d0";
    regs_addresses(89)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"20e0";
    regs_addresses(90)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"20f0";
    regs_addresses(91)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2100";
    regs_addresses(92)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2110";
    regs_addresses(93)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2120";
    regs_addresses(94)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2130";
    regs_addresses(95)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2140";
    regs_addresses(96)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2150";
    regs_addresses(97)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2160";
    regs_addresses(98)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2170";
    regs_addresses(99)(REG_GEM_TESTS_ADDRESS_MSB downto REG_GEM_TESTS_ADDRESS_LSB) <= '0' & x"2180";

    -- Connect read signals
    regs_read_arr(1)(REG_GEM_TESTS_GBT_LOOPBACK_CTRL_LOOP_THROUGH_OH_BIT) <= gbt_loop_through_oh;
    regs_read_arr(2)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_0_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(0);
    regs_read_arr(3)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_0_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_0_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(0);
    regs_read_arr(4)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_0_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_0_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(0);
    regs_read_arr(5)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_1_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(1);
    regs_read_arr(6)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_1_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_1_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(1);
    regs_read_arr(7)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_1_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_1_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(1);
    regs_read_arr(8)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_2_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(2);
    regs_read_arr(9)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_2_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_2_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(2);
    regs_read_arr(10)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_2_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_2_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(2);
    regs_read_arr(11)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_3_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(3);
    regs_read_arr(12)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_3_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_3_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(3);
    regs_read_arr(13)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_3_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_3_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(3);
    regs_read_arr(14)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_4_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(4);
    regs_read_arr(15)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_4_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_4_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(4);
    regs_read_arr(16)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_4_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_4_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(4);
    regs_read_arr(17)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_5_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(5);
    regs_read_arr(18)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_5_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_5_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(5);
    regs_read_arr(19)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_5_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_5_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(5);
    regs_read_arr(20)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_6_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(6);
    regs_read_arr(21)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_6_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_6_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(6);
    regs_read_arr(22)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_6_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_6_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(6);
    regs_read_arr(23)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_7_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(7);
    regs_read_arr(24)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_7_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_7_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(7);
    regs_read_arr(25)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_7_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_7_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(7);
    regs_read_arr(26)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_8_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(8);
    regs_read_arr(27)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_8_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_8_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(8);
    regs_read_arr(28)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_8_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_8_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(8);
    regs_read_arr(29)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_9_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(9);
    regs_read_arr(30)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_9_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_9_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(9);
    regs_read_arr(31)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_9_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_9_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(9);
    regs_read_arr(32)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_10_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(10);
    regs_read_arr(33)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_10_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_10_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(10);
    regs_read_arr(34)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_10_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_10_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(10);
    regs_read_arr(35)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_11_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(11);
    regs_read_arr(36)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_11_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_11_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(11);
    regs_read_arr(37)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_11_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_11_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(11);
    regs_read_arr(38)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_12_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(12);
    regs_read_arr(39)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_12_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_12_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(12);
    regs_read_arr(40)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_12_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_12_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(12);
    regs_read_arr(41)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_13_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(13);
    regs_read_arr(42)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_13_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_13_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(13);
    regs_read_arr(43)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_13_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_13_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(13);
    regs_read_arr(44)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_14_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(14);
    regs_read_arr(45)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_14_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_14_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(14);
    regs_read_arr(46)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_14_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_14_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(14);
    regs_read_arr(47)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_15_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(15);
    regs_read_arr(48)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_15_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_15_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(15);
    regs_read_arr(49)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_15_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_15_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(15);
    regs_read_arr(50)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_16_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(16);
    regs_read_arr(51)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_16_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_16_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(16);
    regs_read_arr(52)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_16_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_16_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(16);
    regs_read_arr(53)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_17_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(17);
    regs_read_arr(54)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_17_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_17_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(17);
    regs_read_arr(55)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_17_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_17_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(17);
    regs_read_arr(56)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_18_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(18);
    regs_read_arr(57)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_18_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_18_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(18);
    regs_read_arr(58)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_18_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_18_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(18);
    regs_read_arr(59)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_19_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(19);
    regs_read_arr(60)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_19_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_19_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(19);
    regs_read_arr(61)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_19_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_19_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(19);
    regs_read_arr(62)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_20_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(20);
    regs_read_arr(63)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_20_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_20_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(20);
    regs_read_arr(64)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_20_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_20_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(20);
    regs_read_arr(65)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_21_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(21);
    regs_read_arr(66)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_21_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_21_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(21);
    regs_read_arr(67)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_21_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_21_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(21);
    regs_read_arr(68)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_22_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(22);
    regs_read_arr(69)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_22_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_22_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(22);
    regs_read_arr(70)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_22_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_22_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(22);
    regs_read_arr(71)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_23_SYNC_DONE_BIT) <= gbt_loop_sync_done_arr(23);
    regs_read_arr(72)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_23_MEGA_WORD_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_23_MEGA_WORD_CNT_LSB) <= gbt_loop_mega_word_cnt_arr(23);
    regs_read_arr(73)(REG_GEM_TESTS_GBT_LOOPBACK_LINK_23_ERROR_CNT_MSB downto REG_GEM_TESTS_GBT_LOOPBACK_LINK_23_ERROR_CNT_LSB) <= gbt_loop_error_cnt_arr(23);
    regs_read_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_ENABLE_BIT) <= vfat_daqmon_enable;
    regs_read_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_OH_SELECT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_OH_SELECT_LSB) <= vfat_daqmon_oh_select;
    regs_read_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_SELECT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_SELECT_LSB) <= vfat_daqmon_chan_select;
    regs_read_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_GLOBAL_OR_BIT) <= vfat_daqmon_chan_global_or;
    regs_read_arr(76)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT0_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT0_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(0);
    regs_read_arr(76)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT0_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT0_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(0);
    regs_read_arr(77)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT1_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT1_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(1);
    regs_read_arr(77)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT1_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT1_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(1);
    regs_read_arr(78)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT2_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT2_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(2);
    regs_read_arr(78)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT2_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT2_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(2);
    regs_read_arr(79)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT3_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT3_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(3);
    regs_read_arr(79)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT3_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT3_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(3);
    regs_read_arr(80)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT4_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT4_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(4);
    regs_read_arr(80)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT4_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT4_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(4);
    regs_read_arr(81)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT5_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT5_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(5);
    regs_read_arr(81)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT5_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT5_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(5);
    regs_read_arr(82)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT6_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT6_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(6);
    regs_read_arr(82)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT6_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT6_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(6);
    regs_read_arr(83)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT7_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT7_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(7);
    regs_read_arr(83)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT7_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT7_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(7);
    regs_read_arr(84)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT8_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT8_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(8);
    regs_read_arr(84)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT8_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT8_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(8);
    regs_read_arr(85)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT9_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT9_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(9);
    regs_read_arr(85)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT9_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT9_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(9);
    regs_read_arr(86)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT10_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT10_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(10);
    regs_read_arr(86)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT10_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT10_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(10);
    regs_read_arr(87)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT11_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT11_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(11);
    regs_read_arr(87)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT11_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT11_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(11);
    regs_read_arr(88)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT12_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT12_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(12);
    regs_read_arr(88)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT12_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT12_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(12);
    regs_read_arr(89)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT13_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT13_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(13);
    regs_read_arr(89)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT13_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT13_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(13);
    regs_read_arr(90)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT14_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT14_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(14);
    regs_read_arr(90)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT14_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT14_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(14);
    regs_read_arr(91)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT15_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT15_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(15);
    regs_read_arr(91)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT15_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT15_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(15);
    regs_read_arr(92)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT16_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT16_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(16);
    regs_read_arr(92)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT16_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT16_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(16);
    regs_read_arr(93)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT17_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT17_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(17);
    regs_read_arr(93)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT17_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT17_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(17);
    regs_read_arr(94)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT18_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT18_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(18);
    regs_read_arr(94)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT18_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT18_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(18);
    regs_read_arr(95)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT19_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT19_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(19);
    regs_read_arr(95)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT19_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT19_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(19);
    regs_read_arr(96)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT20_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT20_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(20);
    regs_read_arr(96)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT20_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT20_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(20);
    regs_read_arr(97)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT21_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT21_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(21);
    regs_read_arr(97)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT21_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT21_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(21);
    regs_read_arr(98)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT22_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT22_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(22);
    regs_read_arr(98)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT22_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT22_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(22);
    regs_read_arr(99)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT23_GOOD_EVENTS_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT23_GOOD_EVENTS_COUNT_LSB) <= vfat_daqmon_good_evt_cnt_arr(23);
    regs_read_arr(99)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT23_CHANNEL_FIRE_COUNT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_VFAT23_CHANNEL_FIRE_COUNT_LSB) <= vfat_daqmon_chan_fire_cnt_arr(23);

    -- Connect write signals
    gbt_loop_through_oh <= regs_write_arr(1)(REG_GEM_TESTS_GBT_LOOPBACK_CTRL_LOOP_THROUGH_OH_BIT);
    vfat_daqmon_enable <= regs_write_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_ENABLE_BIT);
    vfat_daqmon_oh_select <= regs_write_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_OH_SELECT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_OH_SELECT_LSB);
    vfat_daqmon_chan_select <= regs_write_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_SELECT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_SELECT_LSB);
    vfat_daqmon_chan_global_or <= regs_write_arr(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_GLOBAL_OR_BIT);

    -- Connect write pulse signals
    reset_local <= regs_write_pulse_arr(0);
    vfat_daqmon_reset <= regs_write_pulse_arr(74);

    -- Connect write done signals

    -- Connect read pulse signals

    -- Connect read ready signals

    -- Defaults
    regs_defaults(1)(REG_GEM_TESTS_GBT_LOOPBACK_CTRL_LOOP_THROUGH_OH_BIT) <= REG_GEM_TESTS_GBT_LOOPBACK_CTRL_LOOP_THROUGH_OH_DEFAULT;
    regs_defaults(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_ENABLE_BIT) <= REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_ENABLE_DEFAULT;
    regs_defaults(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_OH_SELECT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_OH_SELECT_LSB) <= REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_OH_SELECT_DEFAULT;
    regs_defaults(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_SELECT_MSB downto REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_SELECT_LSB) <= REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_SELECT_DEFAULT;
    regs_defaults(75)(REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_GLOBAL_OR_BIT) <= REG_GEM_TESTS_VFAT_DAQ_MONITOR_CTRL_VFAT_CHANNEL_GLOBAL_OR_DEFAULT;

    -- Define writable regs
    regs_writable_arr(1) <= '1';
    regs_writable_arr(75) <= '1';

    --==== Registers end ============================================================================

end Behavioral;
