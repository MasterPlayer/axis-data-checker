`timescale 1ns / 1ps



module axis_checker_functional #(
    parameter integer N_BYTES            = 4        ,
    parameter integer TIMER_LIMIT        = 156250000,
    parameter string  MODE               = "SINGLE" , // "ZEROS" "BYTE"
    parameter integer NUMBER_OF_COUNTERS = 2
) (
    input  logic                   CLK                ,
    input  logic                   RESET              ,
    input  logic [(N_BYTES*8)-1:0] S_AXIS_TDATA       ,
    input  logic                   S_AXIS_TVALID      ,
    output logic                   S_AXIS_TREADY      ,
    input  logic                   S_AXIS_TLAST       ,
    input  logic                   MODE_RST_COUNTER   ,
    input  logic [           31:0] PORTION_SIZE       ,
    input  logic                   ENABLE             ,
    input  logic [           31:0] PACKET_SIZE        ,
    input  logic [           31:0] READY_LIMIT        ,
    input  logic [           31:0] NOT_READY_LIMIT    ,
    output logic [(N_BYTES*8)-1:0] DBG_CNT_FILL       ,
    output logic                   DBG_HAS_DATA_ERROR ,
    input  logic                   IGNORE_DATA_ERROR  ,
    input  logic                   IGNORE_PACKET_ERROR,
    output logic [           31:0] DATA_ERROR         ,
    output logic [           31:0] PACKET_ERROR       ,
    output logic [           31:0] DATA_SPEED         ,
    output logic [           31:0] PACKET_SPEED        
);


    parameter integer DATA_WIDTH = (N_BYTES*8);
    parameter integer DATA_WIDTH_CNT = (N_BYTES/NUMBER_OF_COUNTERS)*8;

    logic [NUMBER_OF_COUNTERS-1:0][DATA_WIDTH_CNT-1:0] cnt_fill = '{default:0};
    logic                                              has_data_err_reg  = 1'b0        ;
    logic [                  31:0]                     ready_1_cnt       = '{default:0};
    logic [                  31:0]                     ready_0_cnt       = '{default:0};

    typedef enum { 
        IDLE_ST             ,
        CHK_IS_READY_ST     ,
        CHK_NOT_RDY_ST    
    } fsm;

    fsm  current_state = IDLE_ST;

    logic        save_for_first     = 1'b0        ;
    logic [31:0] timer_cnt          = '{default:0};
    logic [31:0] data_speed_cnt     = '{default:0};
    logic [31:0] packet_speed_cnt   = '{default:0};
    logic        has_packet_err_reg = 1'b0        ;
    logic [31:0] packet_size_cnt    = '{default:0};
    logic [31:0] packet_size_reg    = '{default:0};
    logic [31:0] portion_size_reg   = '{default:0};
    logic [31:0] portion_size_cnt   = '{default:0};




    initial begin : drc_check

        reg drc_error;
        drc_error = 0;

        $display("[%s] : width of each counter : %0d", "AXIS_CHECKER", DATA_WIDTH_CNT);

        if (MODE != "DATA") begin 
            if (MODE != "ZEROS") begin 
                $error("[%s %0d-%0d] Supported mode only for ZEROS or DATA, but not %s", "AXIS_CHECKER", 1, 1, MODE);
                drc_error = 1;                    
            end 
        end 

        if (N_BYTES % NUMBER_OF_COUNTERS != 0) begin 
            $error("[%s %0d-%0d] Assymetric counters and data bus width : DATA width : %0d, Number of Counters %0d", "AXIS_CHECKER", 1, 2, N_BYTES, NUMBER_OF_COUNTERS);
           drc_error = 1;                                
        end 
           

        if (drc_error)
            #1 $finish;
    end 

    always_comb begin
        DBG_CNT_FILL       = cnt_fill;
        DBG_HAS_DATA_ERROR = has_data_err_reg;
    end 



    always_comb begin 
        case (current_state)
            CHK_IS_READY_ST : 
                S_AXIS_TREADY = 1'b1;

            default : 
                S_AXIS_TREADY = 1'b0;

        endcase // current_state
    end 


    always_ff @(posedge CLK) begin : portion_size_reg_processing
        case (current_state)
            IDLE_ST: 
                if (ENABLE) begin 
                    portion_size_reg <= PORTION_SIZE - N_BYTES;
                end else begin 
                    portion_size_reg <= portion_size_reg;
                end

            default :  
                portion_size_reg <= portion_size_reg;
        endcase
    end



    always_ff @(posedge CLK) begin : portion_size_cnt_processing
        if (ENABLE) begin 
            if (S_AXIS_TVALID & S_AXIS_TREADY) begin  
                if (portion_size_cnt < portion_size_reg) begin  
                    portion_size_cnt <= portion_size_cnt + N_BYTES;
                end else begin 
                    portion_size_cnt <= '{default:0};
                end
            end else begin 
                portion_size_cnt <= portion_size_cnt;
            end
        end else begin 
            portion_size_cnt <= '{default:0};
        end
    end

    always_ff @(posedge CLK) begin : packet_size_reg_processing
        case (current_state)
            IDLE_ST: 
                if (ENABLE) begin 
                    packet_size_reg <= PACKET_SIZE;
                end else begin 
                    packet_size_reg <= packet_size_reg;
                end

            default :  
                packet_size_reg <= packet_size_reg;

        endcase
    end

    always_ff @(posedge CLK) begin : current_state_processing
        if (RESET) begin  
            current_state <= IDLE_ST;
        end else begin 

            case (current_state)
                IDLE_ST: 
                    if (ENABLE) begin 
                        current_state <= CHK_IS_READY_ST;
                    end else begin 
                        current_state <= current_state;
                    end

                CHK_IS_READY_ST :
                    if (ready_1_cnt < (READY_LIMIT-1)) begin 
                        current_state <= current_state;
                    end else begin 
                        if (NOT_READY_LIMIT == 0) begin 
                            if (!ENABLE) begin 
                                current_state <= IDLE_ST;
                            end else begin 
                                current_state <= current_state;
                            end
                        end else begin 
                            if (!ENABLE) begin  
                                current_state <= IDLE_ST;
                            end else begin     
                                current_state <= CHK_NOT_RDY_ST;
                            end
                        end
                    end

                CHK_NOT_RDY_ST : 
                    if (ready_0_cnt < (NOT_READY_LIMIT-1)) begin 
                        current_state <= current_state;
                    end else begin 
                        if (!ENABLE) begin  
                            current_state <= IDLE_ST;
                        end else begin 
                            current_state <= CHK_IS_READY_ST;
                        end
                    end

                default :  
                    current_state <= IDLE_ST;

            endcase
        end
    end

    always_ff @(posedge CLK) begin : ready_1_cnt_processing
        case (current_state)
            CHK_IS_READY_ST :
                if (S_AXIS_TREADY & S_AXIS_TVALID) begin  
                    if (ready_1_cnt < READY_LIMIT) begin 
                        ready_1_cnt <= ready_1_cnt + 1;
                    end else begin 
                        ready_1_cnt <= '{default:0};
                    end
                end else begin 
                    ready_1_cnt <= ready_1_cnt;
                end

            default :  
                ready_1_cnt <= '{default:0};
        endcase
    end

    always_ff @(posedge CLK) begin : ready_0_cnt_processing

        case (current_state)
            CHK_NOT_RDY_ST :
                if (ready_0_cnt < NOT_READY_LIMIT) begin  
                    ready_0_cnt <= ready_0_cnt + 1;
                end else begin 
                    ready_0_cnt <= ready_0_cnt;
                end

            default :  
                ready_0_cnt <= '{default:0};

        endcase
    end


    generate 
        if (MODE == "ZEROS") begin : GEN_ZEROS_COUNTER

            always_comb begin 
                cnt_fill <= '{default:0};
            end 

            always_ff @(posedge CLK) begin : has_data_err_reg_processing
                if (ENABLE) begin 
                    if (S_AXIS_TVALID & S_AXIS_TREADY) begin  
                        if (S_AXIS_TDATA == cnt_fill) begin   
                            has_data_err_reg <= 1'b0; 
                        end else begin 
                            has_data_err_reg <= ~IGNORE_DATA_ERROR;
                        end
                    end else begin 
                        has_data_err_reg <= 1'b0;                        
                    end
                end else begin 
                    has_data_err_reg <= 1'b0;
                end
            end
        end // GEN_ZEROS_COUNTER
        



        if (MODE == "DATA") begin : GEN_DATA_COUNTER

            for (genvar cnt_index = 0; cnt_index < NUMBER_OF_COUNTERS; cnt_index++) begin 
     

                always_ff @(posedge CLK) begin : cnt_fill_processing
                    if (RESET) begin  
                        cnt_fill[cnt_index] <= ((2**DATA_WIDTH_CNT) - NUMBER_OF_COUNTERS) + cnt_index;
                    end else begin 
                        if (ENABLE) begin 
                            if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                                if (save_for_first) begin 
                                    cnt_fill[cnt_index] <= S_AXIS_TDATA[((DATA_WIDTH_CNT*(cnt_index+1))-1) : (DATA_WIDTH_CNT*cnt_index)] + NUMBER_OF_COUNTERS;
                                end else begin 
                                    if (cnt_fill[cnt_index] != S_AXIS_TDATA[((DATA_WIDTH_CNT*(cnt_index+1))-1) : (DATA_WIDTH_CNT*cnt_index)]) begin 
                                        cnt_fill[cnt_index] <= S_AXIS_TDATA[((DATA_WIDTH_CNT*(cnt_index+1))-1) : (DATA_WIDTH_CNT*cnt_index)] + NUMBER_OF_COUNTERS;
                                    end else begin 
                                        cnt_fill[cnt_index] <= cnt_fill[cnt_index] + NUMBER_OF_COUNTERS;
                                    end
                                end
                            end else begin         
                                cnt_fill[cnt_index] <= cnt_fill[cnt_index];
                            end
                        end else begin 
                            cnt_fill[cnt_index] <= cnt_fill[cnt_index];
                        end
                    end
                end
            end


            always_ff @(posedge CLK) begin : save_for_first_processing
                if (RESET) begin  
                    save_for_first <= 1'b1;
                end else begin 
                    if (ENABLE) begin 
                        if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                            save_for_first <= 1'b0;
                        end else begin 
                            save_for_first <= save_for_first;
                        end
                    end else begin 
                        save_for_first <= 1'b1;
                    end
                end
            end

            always_ff @(posedge CLK) begin : has_data_err_reg_processing
                if (RESET) begin  
                    has_data_err_reg <= 1'b0;
                end else begin 
                    if (ENABLE) begin 
                        if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                            if (save_for_first) begin 
                                has_data_err_reg <= 1'b0;
                            end else begin 
                                if (S_AXIS_TDATA == cnt_fill) begin  
                                    has_data_err_reg <= 1'b0;
                                end else begin 
                                    has_data_err_reg <= 1'b1;
                                end
                            end
                        end else begin 
                            has_data_err_reg <= 1'b0;
                        end
                    end else begin 
                        has_data_err_reg <= 1'b0;
                    end
                end
            end
        end // GEN_DATA_COUNTER

    endgenerate



    always_ff @(posedge CLK) begin : DATA_ERROR_processing
        if (RESET) begin  
            DATA_ERROR <= '{default:0} ;
        end else begin 
            if (ENABLE) begin 
                if (has_data_err_reg) begin  
                    DATA_ERROR <= DATA_ERROR + 1;
                end else begin 
                    DATA_ERROR <= DATA_ERROR;
                end
            end else begin 
                DATA_ERROR <= '{default:0} ;
            end
            
        end
    end

    always_ff @(posedge CLK) begin : timer_cnt_processing
        if (RESET) begin  
            timer_cnt <= '{default:0} ;
        end else begin 
            if (timer_cnt < (TIMER_LIMIT-1)) begin  
                timer_cnt <= timer_cnt + 1;
            end else begin 
                timer_cnt <= '{default:0} ;
            end
        end
    end

    always_ff @(posedge CLK) begin : data_speed_cnt_processing
        if (RESET) begin  
            data_speed_cnt <= '{default:0};
        end else begin 
            if (timer_cnt < (TIMER_LIMIT-1)) begin  
                if (S_AXIS_TREADY & S_AXIS_TVALID) begin 
                    data_speed_cnt <= data_speed_cnt + N_BYTES;
                end else begin 
                    data_speed_cnt <= data_speed_cnt;
                end
            end else begin 
                data_speed_cnt <= '{default:0};
            end
        end
    end

    always_ff @(posedge CLK) begin : data_speed_reg_processing
        if (RESET) begin  
            DATA_SPEED <= '{default:0} ;
        end else begin 
            if (timer_cnt < (TIMER_LIMIT-1)) begin  
                DATA_SPEED <= DATA_SPEED;
            end else begin 
                if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                    DATA_SPEED <= data_speed_cnt + N_BYTES;
                end else begin 
                    DATA_SPEED <= data_speed_cnt;
                end
            end
        end
    end


    always_ff @(posedge CLK) begin : packet_size_cnt_processing
        if (RESET) begin  
            packet_size_cnt <= 32'h00000001;
        end else begin 
            if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                if (S_AXIS_TLAST) begin  
                    packet_size_cnt <= 32'h00000001;
                end else begin 
                    packet_size_cnt <= packet_size_cnt + 1;
                end
            end else begin 
                packet_size_cnt <= packet_size_cnt;
            end
        end
    end

    always_ff @(posedge CLK) begin : has_packet_err_reg_processing
        if (RESET) begin  
            has_packet_err_reg <= 1'b0;
        end else begin 
            if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                if (S_AXIS_TLAST) begin  
                    if (packet_size_reg == 0) begin  
                        has_packet_err_reg <= 1'b0;
                    end else begin 
                        if (packet_size_cnt == packet_size_reg) begin  
                            has_packet_err_reg <= 1'b0;
                        end else begin 
                            has_packet_err_reg <= ~IGNORE_PACKET_ERROR;
                        end
                    end
                end else begin 
                    has_packet_err_reg <= 1'b0;
                end
            end else begin 
                has_packet_err_reg <= 1'b0;
            end

        end 
    end

    always_ff @(posedge CLK) begin : PACKET_ERROR_processing
        if (RESET) begin  
            PACKET_ERROR <= '{default:0};
        end else begin 
            if (has_packet_err_reg) begin 
                PACKET_ERROR <= PACKET_ERROR + 1;
            end else begin 
                PACKET_ERROR <= PACKET_ERROR;
            end
        end
    end

    always_ff @(posedge CLK) begin : PACKET_SPEED_processing
        if (timer_cnt < (TIMER_LIMIT-1)) begin  
            PACKET_SPEED <= PACKET_SPEED;
        end else begin 
            if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                if (S_AXIS_TLAST) begin  
                    PACKET_SPEED <= packet_speed_cnt + 1;
                end else begin 
                    PACKET_SPEED <= PACKET_SPEED;
                end
            end else begin 
                PACKET_SPEED <= PACKET_SPEED;
            end
        end
    end

    always_ff @(posedge CLK) begin : packet_speed_cnt_processing
        if (timer_cnt < (TIMER_LIMIT-1)) begin  
            if (S_AXIS_TVALID & S_AXIS_TREADY) begin 
                if (S_AXIS_TLAST) begin  
                    packet_speed_cnt <= packet_speed_cnt + 1;
                end else begin 
                    packet_speed_cnt <= packet_speed_cnt;
                end
            end else begin 
                packet_speed_cnt <= packet_speed_cnt;
            end
        end else begin 
            packet_speed_cnt <= '{default:0};
        end
    end




endmodule
