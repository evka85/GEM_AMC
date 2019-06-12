library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
use work.ipbus.all;

package sca_pkg is

    -- channels
    constant SCA_CHANNEL_CONFIG   : std_logic_vector(7 downto 0) := x"00";
    constant SCA_CHANNEL_GPIO     : std_logic_vector(7 downto 0) := x"02";
    constant SCA_CHANNEL_JTAG     : std_logic_vector(7 downto 0) := x"13";
    constant SCA_CHANNEL_ADC      : std_logic_vector(7 downto 0) := x"14";

    -- config reg commands
    constant SCA_CMD_CONFIG_WRITE_CRB   : std_logic_vector(7 downto 0) := x"02"; 
    constant SCA_CMD_CONFIG_WRITE_CRC   : std_logic_vector(7 downto 0) := x"04"; 
    constant SCA_CMD_CONFIG_WRITE_CRD   : std_logic_vector(7 downto 0) := x"06"; 

    -- GPIO commands
    constant SCA_CMD_GPIO_SET_DIR       : std_logic_vector(7 downto 0) := x"20"; 
    constant SCA_CMD_GPIO_READ_DIR      : std_logic_vector(7 downto 0) := x"21"; 
    constant SCA_CMD_GPIO_SET_OUT       : std_logic_vector(7 downto 0) := x"10"; 

    -- ADC commands
    constant SCA_CMD_ADC_SET_MUX        : std_logic_vector(7 downto 0) := x"30"; 
    constant SCA_CMD_ADC_READ_MUX       : std_logic_vector(7 downto 0) := x"31"; 
    constant SCA_CMD_ADC_READ           : std_logic_vector(7 downto 0) := x"b2"; 

    -- JTAG commands and constants
    constant SCA_CFG_JTAG_FREQ          : std_logic_vector(31 downto 0) := x"09000000"; -- Use 2MHz JTAG clk frequency by default (can go higher, no prob)  
    constant SCA_CFG_JTAG_CTRL_REG      : std_logic_vector(31 downto 0) := x"00000c00"; -- TX on falling edge, shift out LSB 
    constant SCA_CMD_JTAG_SET_FREQ      : std_logic_vector(7 downto 0) := x"90"; 
    constant SCA_CMD_JTAG_SET_CTRL_REG  : std_logic_vector(7 downto 0) := x"80"; 
    constant SCA_CMD_JTAG_SET_TDO0      : std_logic_vector(7 downto 0) := x"00";
    constant SCA_CMD_JTAG_SET_TMS0      : std_logic_vector(7 downto 0) := x"40";
    constant SCA_CMD_JTAG_READ_TDI0     : std_logic_vector(7 downto 0) := x"01";
    constant SCA_CMD_JTAG_GO            : std_logic_vector(7 downto 0) := x"a2";

    -- default values
    -- for GPIO, note that the bytes are in reverse order, meaning that e.g. 0x00000080 only sets bit 31
    constant SCA_DEFAULT_GPIO_OUTPUT    : std_logic_vector(31 downto 0) := x"f00000f0"; -- PROG_B = high, not driving INIT_B, GPIO that go to FPGA are all set low, and VFAT3 reset in OHv3c are set low

    type t_sca_reply is record
        channel           : std_logic_vector(7 downto 0);
        error             : std_logic_vector(7 downto 0);
        length            : std_logic_vector(7 downto 0);
        data              : std_logic_vector(31 downto 0);
    end record;

    type t_sca_command is record
        channel           : std_logic_vector(7 downto 0);
        command           : std_logic_vector(7 downto 0);
        length            : std_logic_vector(7 downto 0);
        data              : std_logic_vector(31 downto 0);
    end record;

    type t_sca_command_array is array(integer range <>) of t_sca_command;
    type t_sca_reply_array is array(integer range <>) of t_sca_reply;

    -- the messages in this array are executed in sequence after SCA CONTOLLER reset followed by SCA chip reset
    constant SCA_CONFIG_SEQUENCE : t_sca_command_array(0 to 6) := (
        (channel => SCA_CHANNEL_CONFIG, command => SCA_CMD_CONFIG_WRITE_CRB, length => x"01", data => x"00000004"),         -- enable GPIO
        (channel => SCA_CHANNEL_CONFIG, command => SCA_CMD_CONFIG_WRITE_CRC, length => x"01", data => x"00000000"),         -- disable I2C
        (channel => SCA_CHANNEL_CONFIG, command => SCA_CMD_CONFIG_WRITE_CRD, length => x"01", data => x"00000018"),         -- 0x18 enable JTAG and ADC
        (channel => SCA_CHANNEL_GPIO, command => SCA_CMD_GPIO_SET_DIR, length => x"04", data => x"0fffff8f"),               -- set PROG_B, those that go to FPGA, and the ones connected to VFAT3 resets in OHv3c as outputs
        (channel => SCA_CHANNEL_GPIO, command => SCA_CMD_GPIO_SET_OUT, length => x"04", data => SCA_DEFAULT_GPIO_OUTPUT),   -- set GPIO ouputs to default
        (channel => SCA_CHANNEL_JTAG, command => SCA_CMD_JTAG_SET_CTRL_REG, length => x"04", data => SCA_CFG_JTAG_CTRL_REG),-- set JTAG control reg defaults
        (channel => SCA_CHANNEL_JTAG, command => SCA_CMD_JTAG_SET_FREQ, length => x"04", data => SCA_CFG_JTAG_FREQ)         -- set default JTAG clk frequency
    );
    
end sca_pkg;
