`timescale 1 ns / 1 ps

module axi_checker_lite #(
    parameter FREQ_HZ              = 250000000,
    parameter N_BYTES              = 4        ,
    parameter MODE                 = "SINGLE" , // "SINGLE", "ZEROS", "BYTE"
    parameter NUMBER_OF_COUNTERS   = 2        ,
    parameter DEFAULT_READY_LIMIT  = 4096     ,
    parameter DEFAULT_BUSY_LIMIT   = 0        ,
    parameter DEFAULT_PACKET_SIZE  = 4096     ,
    parameter DEFAULT_PORTION_SIZE = 1048576   
) (
    // AXI-LITE interface
    input                            aclk              ,
    input                            aresetn           ,
    input        [              5:0] awaddr            ,
    input        [              2:0] awprot            ,
    input                            awvalid           ,
    output logic                     awready           ,
    input        [             31:0] wdata             ,
    input        [              3:0] wstrb             ,
    input                            wvalid            ,
    output logic                     wready            ,
    output logic [              1:0] bresp             ,
    output logic                     bvalid            ,
    input                            bready            ,
    input        [              5:0] araddr            ,
    input        [              2:0] arprot            ,
    input                            arvalid           ,
    output logic                     arready           ,
    output logic [             31:0] rdata             ,
    output logic [              1:0] rresp             ,
    output logic                     rvalid            ,
    input                            rready            ,
    // DEBUG group
    output logic [((N_BYTES*8)-1):0] DBG_CNT_FILL      ,
    output logic                     DBG_HAS_DATA_ERROR,

    input  logic [  (N_BYTES*8)-1:0] S_AXIS_TDATA      ,
    input  logic                     S_AXIS_TVALID     ,
    output logic                     S_AXIS_TREADY     ,
    input  logic                     S_AXIS_TLAST       
);

    localparam integer ADDR_LSB = 2;
    localparam integer ADDR_OPT = 3;


    logic        chk_reset              ;
    logic        chk_enable             ;
    logic [31:0] chk_packet_size        ;
    logic [31:0] chk_portion_size       ;
    logic [31:0] chk_ready_limit        ;
    logic [31:0] chk_not_ready_limit    ;
    logic        chk_ignore_data_error  ;
    logic        chk_ignore_packet_error;
    logic [31:0] chk_data_error         ;
    logic [31:0] chk_packet_error       ;
    logic [31:0] chk_data_speed         ;
    logic [31:0] chk_packet_speed       ;

    logic chk_mode_rst_counter;

    logic [12:0][31:0] register;

    logic aw_en = 1'b1;

    always_comb begin : to_user_logic_assignment_group
        chk_reset               = register[0][0];
        
        chk_enable              = register[1][0];
        chk_ignore_data_error   = register[1][1];
        chk_ignore_packet_error = register[1][2];
        chk_mode_rst_counter    = register[1][3];

        chk_packet_size         = register[2];
        chk_ready_limit         = register[3];
        chk_not_ready_limit     = register[4];
        chk_portion_size        = register[12];
    end 

    always_comb begin : from_usr_logic_assignment_group
        register[5]  = chk_data_error;
        register[6]  = chk_packet_error;
        register[7]  = chk_data_speed;
        register[8]  = chk_packet_speed;
        register[9]  = FREQ_HZ;
        register[10] = N_BYTES;
    end 

    /**/
    always_ff @(posedge aclk) begin : aw_en_processing 
        if (!aresetn) 
            aw_en <= 1'b1;
        else
            if (!awready & awvalid & wvalid & aw_en)
                aw_en <= 1'b0;
            else
                if (bready & bvalid)
                    aw_en <= 1'b1;
    end 

    /**/
    always_ff @(posedge aclk) begin : awready_processing 
        if (!aresetn)
            awready <= 1'b0;
        else
            if (!awready & awvalid & wvalid & aw_en)
                awready <= 1'b1;
            else 
                awready <= 1'b0;
    end 



    always_ff @(posedge aclk) begin : wready_processing 
        if (!aresetn)
            wready <= 1'b0;
        else
            if (!wready & wvalid & awvalid & aw_en)
                wready <= 1'b1;
            else
                wready <= 1'b0;

    end 



    always_ff @(posedge aclk) begin : bvalid_processing
        if (!aresetn)
            bvalid <= 1'b0;
        else
            // if (awvalid & awready & wvalid & wready & ~bvalid)
            if (wvalid & wready & awvalid & awready & ~bvalid)
                bvalid <= 1'b1;
            else
                if (bvalid & bready)
                    bvalid <= 1'b0;

    end 



    always_ff @(posedge aclk) begin : arready_processing 
        if (!aresetn)
            arready <= 1'b0;
        else
            if (!arready & arvalid)
                arready <= 1'b1;
            else
                arready <= 1'b0;
            
    end



    always_ff @(posedge aclk) begin : rvalid_processing
        if (!aresetn)
            rvalid <= 1'b0;
        else
            if (arvalid & arready & ~rvalid)
                rvalid <= 1'b1;
        else
            if (rvalid & rready)
                rvalid <= 1'b0;

    end 


    always_ff @(posedge aclk) begin : rdata_processing
        if (!aresetn)
            rdata <= '{default:0};
        else
            if (arvalid & arready & ~rvalid)
                case (araddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB])
                    'h0     : rdata <= register[0];
                    'h1     : rdata <= register[1];
                    'h2     : rdata <= register[2];
                    'h3     : rdata <= register[3];
                    'h4     : rdata <= register[4];
                    'h5     : rdata <= register[5];
                    'h6     : rdata <= register[6];
                    'h7     : rdata <= register[7];
                    'h8     : rdata <= register[8];
                    'h9     : rdata <= register[9];
                    'hA     : rdata <= register[10];
                    'hB     : rdata <= register[11];
                    'hC     : rdata <= register[12];
                    default : rdata <= rdata;
                endcase // araddr
    end 



    always_ff @(posedge aclk) begin : rresp_processing
        if (!aresetn)
            rresp <= '{default:0};
        else
            if (arvalid & arready & ~rvalid)
                case (araddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB])
                    'h0     : rresp <= '{default:0};
                    'h1     : rresp <= '{default:0};
                    'h2     : rresp <= '{default:0};
                    'h3     : rresp <= '{default:0};
                    'h4     : rresp <= '{default:0};
                    'h5     : rresp <= '{default:0};
                    'h6     : rresp <= '{default:0};
                    'h7     : rresp <= '{default:0};
                    'h8     : rresp <= '{default:0};
                    'h9     : rresp <= '{default:0};
                    'hA     : rresp <= '{default:0};
                    'hB     : rresp <= '{default:0};
                    'hC     : rresp <= '{default:0};
                    default : rresp <= 'b10;
                endcase; // araddr
    end                     



    always_ff @(posedge aclk) begin : bresp_processing
        if (!aresetn)
            bresp <= '{default:0};
        else
            if (awvalid & awready & wvalid & wready & ~bvalid)
                if (awaddr >= 0 | awaddr <= 12 )
                    bresp <= '{default:0};
                else
                    bresp <= 'b10;
    end

    always_ff @(posedge aclk) begin : reg_0_processing
        if (!aresetn) 
            register[0] <= 32'h00000001;
        else
            if (awvalid & awready & wvalid & wready)
                if (awaddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB] == 'h00)
                    register[0] <= wdata;
    end 

    always_ff @(posedge aclk) begin : reg_1_processing
        if (!aresetn) 
            register[1] <= '{default:0};
        else
            if (awvalid & awready & wvalid & wready)
                if (awaddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB] == 'h01)
                    register[1] <= wdata;
    end 

    always_ff @(posedge aclk) begin : reg_2_processing
        if (!aresetn) 
            register[2] <= DEFAULT_PACKET_SIZE;
        else
            if (awvalid & awready & wvalid & wready)
                if (awaddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB] == 'h02)
                    register[2] <= wdata;
    end 

    always_ff @(posedge aclk) begin : reg_3_processing
        if (!aresetn) 
            register[3] <= DEFAULT_READY_LIMIT;
        else
            if (awvalid & awready & wvalid & wready)
                if (awaddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB] == 'h03)
                    register[3] <= wdata;
    end 

    always_ff @(posedge aclk) begin : reg_4_processing
        if (!aresetn) 
            register[4] <= DEFAULT_BUSY_LIMIT;
        else
            if (awvalid & awready & wvalid & wready)
                if (awaddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB] == 'h04)
                    register[4] <= wdata;
    end 

    always_ff @(posedge aclk) begin : reg_12_processing 
        if (!aresetn)
            register[12] <= DEFAULT_PORTION_SIZE;
        else 
            if (awvalid & awready & wvalid & wready)
                if (awaddr[(ADDR_OPT + ADDR_LSB) : ADDR_LSB] == 'h0C)
                    register[12] <= wdata;

    end 



    axis_checker_functional #(
        .N_BYTES           (N_BYTES           ),
        .TIMER_LIMIT       (FREQ_HZ           ),
        .MODE              (MODE              ),
        .NUMBER_OF_COUNTERS(NUMBER_OF_COUNTERS)
    ) axis_checker_functional_inst (
        .CLK                (aclk                   ),
        .RESET              (chk_reset              ),
        
        .S_AXIS_TDATA       (S_AXIS_TDATA           ),
        .S_AXIS_TVALID      (S_AXIS_TVALID          ),
        .S_AXIS_TREADY      (S_AXIS_TREADY          ),
        .S_AXIS_TLAST       (S_AXIS_TLAST           ),
        
        .DBG_CNT_FILL       (DBG_CNT_FILL           ),
        .DBG_HAS_DATA_ERROR (DBG_HAS_DATA_ERROR     ),
        
        
        .MODE_RST_COUNTER   (chk_mode_rst_counter   ),
        .ENABLE             (chk_enable             ),
        .PACKET_SIZE        (chk_packet_size        ),
        .PORTION_SIZE       (chk_portion_size       ),
        
        .READY_LIMIT        (chk_ready_limit        ),
        .NOT_READY_LIMIT    (chk_not_ready_limit    ),
        
        .IGNORE_DATA_ERROR  (chk_ignore_data_error  ),
        .IGNORE_PACKET_ERROR(chk_ignore_packet_error),
        
        .DATA_ERROR         (chk_data_error         ),
        .PACKET_ERROR       (chk_packet_error       ),
        .DATA_SPEED         (chk_data_speed         ),
        .PACKET_SPEED       (chk_packet_speed       )
    );







endmodule
