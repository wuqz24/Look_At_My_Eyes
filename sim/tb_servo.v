`timescale 1ns/1ps
module tb_servo;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,armed=0,frame_tick=0,alive=1,valid=1,follow=0;
    reg [11:0] cx=1100,cy=600;
    wire pan,tilt,moving,startup_done,fault_safe,limit_q;
    wire [11:0] pu,tu;
    integer i,k,high_count;
    reg [11:0] saved;
    // In the real design follow_enable is driven by hdmi_mixer (it gates the PWM on a valid
    // colour target). The testbench must drive it as well, otherwise the input floats to z/x
    // and pan_pwm collapses to X (this is why the suite failed after servo_control gained
    // the port on 2026-09-19).
    servo_control #(.CLK_HZ(1000000),.SELFTEST_HOLD_MS(1)) dut(.clk(clk),.rst_n(rst_n),.armed(armed),
        .follow_enable(follow),.frame_tick(frame_tick),.source_alive(alive),.target_valid(valid),
        .cx(cx),.cy(cy),
        .pan_pwm(pan),.tilt_pwm(tilt),.moving(moving),.pan_us(pu),.tilt_us(tu),
        .startup_done(startup_done),.fault_safe(fault_safe),.limit(limit_q));
    task tick;
        begin @(negedge clk); frame_tick=1; @(negedge clk); frame_tick=0; end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        tick;
        // The boot self-test is intentionally independent of ARM. ARM only
        // gates tracking after the self-test has completed.
        repeat(100) @(negedge clk);
        tick;
        repeat(100) @(negedge clk);
        if(!dut.selftest_state) $fatal(1,"startup self-test did not begin");
        armed=1; follow=0; tick;
        // Startup must exercise both axes around center before tracking is allowed.
        begin : startup_check
            integer cycles;
            reg saw_pan_low, saw_pan_high, saw_tilt_low, saw_tilt_high;
            saw_pan_low=0; saw_pan_high=0; saw_tilt_low=0; saw_tilt_high=0;
            for(cycles=0; cycles<20000 && !startup_done; cycles=cycles+1) begin
                if((cycles % 100)==0) tick; else @(negedge clk);
                if(pu==1450) saw_pan_low=1;
                if(pu==1550) saw_pan_high=1;
                if(tu==1450) saw_tilt_low=1;
                if(tu==1550) saw_tilt_high=1;
            end
            if(!startup_done || !saw_pan_low || !saw_pan_high || !saw_tilt_low || !saw_tilt_high)
                $fatal(1,"startup self-test did not complete both axes");
            if(pu!=1500 || tu!=1500 || fault_safe) $fatal(1,"startup did not finish centered");
        end
        cx=640; cy=360; follow=1; tick;
        if(pu!=1500 || tu!=1500) $fatal(1,"centered target moved the servos");
        if(dut.pan_q!=6000 || dut.tilt_q!=6000) $fatal(1,"centered target moved the pulse command");
        // The command is kept in 1/4 us units, so a single frame of a 120 px
        // error is a 0.75 us step that integer microseconds cannot show.  The
        // error filter adds one frame before the step becomes non-zero.
        cx=760; repeat(2) tick;
        if(dut.pan_q<=6000) $fatal(1,"right-side target did not increase the pan command");
        cx=520;
        repeat(12) tick;
        if(dut.pan_q>=6000) $fatal(1,"left-side target did not reverse pan movement");
        cx=640; cy=440; repeat(2) tick;
        if(dut.tilt_q<=6000) $fatal(1,"lower target did not increase tilt command");
        cy=280;
        repeat(12) tick;
        if(dut.tilt_q>=6000) $fatal(1,"upper target did not reverse tilt movement");
        cx=1100; cy=600; tick;
        // Request updates inside the PWM period; active pulse must retain the latched width.
        while(dut.phase!=0) @(negedge clk);
        saved=(dut.pan_ticks_q+3)>>2;
        high_count=0;
        for(i=0;i<20000;i=i+1) begin
            if(pan) high_count=high_count+1;
            if(i==100) frame_tick=1; else frame_tick=0;
            @(negedge clk);
        end
        if(high_count!=saved) $fatal(1,"pulse changed mid-period %d %d",high_count,saved);
        for(k=0;k<150;k=k+1) begin tick; repeat(20) @(negedge clk); end
        if(pu>1800 || pu<1200 || tu>1800 || tu<1200 || pu!=1800) $fatal(1,"clamp");
        valid=0; saved=pu;
        repeat(20) tick;
        if(pu!=saved) $fatal(1,"lost target moves");
        alive=0; @(negedge clk); if(pan || tilt || !fault_safe) $fatal(1,"source failsafe");
        // A recovered video source must restart the startup sequence instead of
        // reusing the old tracking position.
        alive=1; tick;
        repeat(5) @(negedge clk);
        if(startup_done) $fatal(1,"fault recovery reused old startup state");
        for(i=0;i<10000;i=i+1) begin
            if((i % 100)==0) tick; else @(negedge clk);
        end
        if(!startup_done || pu!=1500 || tu!=1500) $fatal(1,"fault recovery did not recenter");
        armed=0; @(negedge clk); if(pan || tilt) $fatal(1,"disarm");
        // After self-test, keep the servo centered until tracking is armed.
        if(pu!=1500 || tu!=1500) $fatal(1,"disarmed servo did not return to center");
        armed=1; repeat(250010) @(negedge clk);
        if(pan || tilt) $fatal(1,"watchdog");
        $display("PASS servo: disarmed startup, pulse latching, clamps, loss hold, source watchdog");
        $finish;
    end
endmodule
