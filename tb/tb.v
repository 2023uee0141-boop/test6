
`timescale 1ns/1ps

module tb_apb4;

    // APB4 signals
    reg         PCLK;
    reg         PRESETn;
    reg         PSEL;
    reg         PENABLE;
    reg         PWRITE;
    reg  [31:0] PADDR;
    reg  [31:0] PWDATA;
    reg  [3:0]  PSTRB;
    reg  [2:0]  PPROT;

    wire [31:0] PRDATA;
    wire        PREADY;
    wire        PSLVERR;

    // Simple APB4 slave model
    reg [31:0] mem [0:15];
    reg [31:0] read_data;
    reg        ready;
    reg        error;

    integer i;

    assign PREADY  = ready;
    assign PRDATA  = read_data;
    assign PSLVERR = error;

    // Clock: 10 ns period
    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    // Slave response model
    // One wait cycle for every access
    initial begin
        ready     = 1'b0;
        read_data = 32'b0;
        error     = 1'b0;

        for (i = 0; i < 16; i = i + 1)
            mem[i] = 32'b0;
    end

    // Perform writes when the APB access phase completes
    always @(posedge PCLK) begin
        if (!PRESETn) begin
            ready     <= 1'b0;
            read_data <= 32'b0;
            error     <= 1'b0;
        end else begin
            // Default: ready becomes high during an access.
            if (PSEL && PENABLE && !ready)
                ready <= 1'b1;
            else
                ready <= 1'b0;

            if (PSEL && PENABLE && PREADY) begin
                if (PWRITE) begin
                    if (PADDR < 64) begin
                        if (PSTRB[0]) mem[PADDR[5:2]][7:0]
                                           <= PWDATA[7:0];
                        if (PSTRB[1]) mem[PADDR[5:2]][15:8]
                                           <= PWDATA[15:8];
                        if (PSTRB[2]) mem[PADDR[5:2]][23:16]
                                           <= PWDATA[23:16];
                        if (PSTRB[3]) mem[PADDR[5:2]][31:24]
                                           <= PWDATA[31:24];
                    end
                end else begin
                    if (PADDR < 64)
                        read_data <= mem[PADDR[5:2]];
                    else
                        read_data <= 32'b0;
                end
            end
        end
    end

    // APB4 master tasks
    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(negedge PCLK);
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b1;
            PADDR   = addr;
            PWDATA  = data;
            PSTRB   = strb;
            PPROT   = 3'b000;

            // Setup phase
            @(negedge PCLK);
            PENABLE = 1'b1;

            // Access phase; hold signals until PREADY
            while (PREADY !== 1'b1)
                @(negedge PCLK);

            // Transfer completes at the next rising edge
            @(posedge PCLK);
            #1;
            $display("[%0t ns] WRITE addr=%h data=%h strb=%b",
                     $time, addr, data, strb);

            @(negedge PCLK);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
        end
    endtask

    task apb_read;
        input [31:0] addr;
        input [31:0] expected;
        begin
            @(negedge PCLK);
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = addr;
            PWDATA  = 32'b0;
            PSTRB   = 4'b0000;
            PPROT   = 3'b000;

            // Setup phase
            @(negedge PCLK);
            PENABLE = 1'b1;

            // Wait until slave is ready
            while (PREADY !== 1'b1)
                @(negedge PCLK);

            @(posedge PCLK);
            #1;
            $display("[%0t ns] READ  addr=%h data=%h expected=%h %s",
                     $time, addr, read_data, expected,
                     (read_data === expected) ? "PASS" : "CHECK");

            if (read_data !== expected)
                $display("ERROR: Read-data mismatch!");

            @(negedge PCLK);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
        end
    endtask

    // Main stimulus
    initial begin
        PRESETn = 1'b0;
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = 32'b0;
        PWDATA  = 32'b0;
        PSTRB   = 4'b0000;
        PPROT   = 3'b000;

        // Reset
        repeat (3) @(negedge PCLK);
        PRESETn = 1'b1;

        // Full-word write and read
        apb_write(32'h0000_0004, 32'h1234_ABCD, 4'b1111);
        apb_read (32'h0000_0004, 32'h1234_ABCD);

        // Partial write: update only the lowest byte
        apb_write(32'h0000_0004, 32'h0000_005A, 4'b0001);
        apb_read (32'h0000_0004, 32'h1234_AB5A);

        // Another independent address
        apb_write(32'h0000_0008, 32'hDEAD_BEEF, 4'b1111);
        apb_read (32'h0000_0008, 32'hDEAD_BEEF);

        // Finish
        repeat (3) @(negedge PCLK);
        $display("APB4 basic simulation completed.");
        $finish;
    end

    // Waveform dump for GTKWave or another VCD viewer
    initial begin
        $dumpfile("tb_apb4.vcd");
        $dumpvars(0, tb_apb4);
    end

endmodule
