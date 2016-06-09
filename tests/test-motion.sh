# Run with ./run-tests.sh

test_wait_for_motion_int() {
    cat > test.py <<-EOF
	wait_for_motion(consecutive_frames=10)
	EOF
    stbt run -v test.py
}

test_wait_for_motion_str() {
    cat > test.py <<-EOF
	wait_for_motion(consecutive_frames='10/10')
	EOF
    stbt run -v test.py
}

test_wait_for_motion_no_motion_int() {
    cat > test.py <<-EOF
	wait_for_motion(consecutive_frames=10, timeout_secs=1)
	EOF
    ! stbt run -v --source-pipeline="videotestsrc ! imagefreeze" test.py
}

test_wait_for_motion_no_motion_str() {
    cat > test.py <<-EOF
	wait_for_motion(consecutive_frames='10/10', timeout_secs=1)
	EOF
    ! stbt run -v --source-pipeline="videotestsrc ! imagefreeze" test.py
}

test_wait_for_motion_with_mask_reports_motion() {
    cat > test.py <<-EOF
	wait_for_motion(mask="$testdir/videotestsrc-mask-video.png")
	EOF
    stbt run -v test.py
}

test_wait_for_motion_with_mask_does_not_report_motion() {
    cat > test.py <<-EOF
	wait_for_motion(
	    mask="$testdir/videotestsrc-mask-no-video.png", timeout_secs=1)
	EOF
    ! stbt run -v test.py
}

test_wait_for_motion_nonexistent_mask() {
    cat > test.py <<-EOF
	wait_for_motion(mask="idontexist.png")
	press("OK")
	wait_for_motion(mask="idontexist.png")
	EOF
    timeout 10 stbt run -v test.py &> test.log
    local ret=$?
    [ $ret -ne $timedout -a $ret -ne 0 ] || fail "Unexpected exit status $ret"
    grep -q "No such mask file: idontexist.png" test.log ||
        fail "Expected 'No such mask file: idontexist.png' but saw '$(
            grep 'No such mask file' test.log | head -n1)'"
}

test_wait_for_motion_with_high_noisethreshold_reports_motion() {
    cat > test.py <<-EOF
	wait_for_motion(noise_threshold=1.0)
	EOF
    stbt run -v test.py
}

test_wait_for_motion_with_low_noisethreshold_does_not_report_motion() {
    cat > test.py <<-EOF
	wait_for_motion(noise_threshold=0.0, timeout_secs=1)
	EOF
    ! stbt run -v test.py
}

test_detect_motion_reports_motion() {
    cat > test.py <<-EOF
	# Should report motion
	for motion_result in detect_motion():
	    assert bool(motion_result) == motion_result.motion
	    if motion_result:
	        # videotestsrc has motion in bottom right corner:
	        assert motion_result.region == stbt.Region(
	            240, 180, right=320, bottom=240)
	        import sys
	        sys.exit(0)
	    else:
	        raise Exception("Motion not reported.")
	raise Exception("Timeout occured without any result reported.")
	EOF
    stbt run -v test.py
}

test_detect_motion_reports_valid_timestamp() {
    cat > test.py <<-EOF
	import time
	
	start_time = time.time()
	last_timestamp = None
	for motion_result in detect_motion():
	    assert motion_result.time >= start_time
	    if last_timestamp != None:
	        if motion_result.time - last_timestamp >= 0:
	            import sys
	            assert motion_result.time <= time.time()
	            sys.exit(0)
	        else:
	            raise Exception("Invalid timestamps reported: %f - %f." % (
	                            last_timestamp,
	                            motion_result.time))
	    if motion_result.time == None:
	        raise Exception("Empty timestamp reported.")
	    last_timestamp = motion_result.time
	raise Exception("Timeout occured without any result reported.")
	EOF
    stbt run -v test.py
}

test_detect_motion_reports_no_motion() {
    cat > test.py <<-EOF
	# Should not report motion
	for motion_result in detect_motion(
	        mask="$testdir/videotestsrc-mask-no-video.png"):
	    assert bool(motion_result) == motion_result.motion
	    if not motion_result:
	        import sys
	        sys.exit(0)
	    else:
	        raise Exception("Motion incorrectly reported.")
	raise Exception("Timeout occured without any result reported.")
	EOF
    stbt run -v test.py
}

test_detect_motion_times_out() {
    cat > test.py <<-EOF
	for motion_result in detect_motion(timeout_secs=1):
	    pass
	EOF
    stbt run -v test.py
}

test_detect_motion_with_debug_output_does_not_segfault_without_mask() {
    cat > test.py <<-EOF
	wait_for_motion(timeout_secs=1)
	EOF
    stbt run -vv test.py  # creates stbt-debug

    if [ $? -eq 0 ] && [ -d "stbt-debug" ] && [ "$leave_scratch_dir" != "true" ]; then
        rm -rf "stbt-debug"
    fi
}

test_detect_motion_times_out_during_yield() {
    cat > test.py <<-EOF
	i = 0
	for motion_result in detect_motion(timeout_secs=1):
	    import time
	    time.sleep(2)
	    i += 1
	assert i == 1
	EOF
    stbt run -v test.py
}

test_detect_motion_changing_mask() {
    # Tests that we can change the mask given to motiondetect.
    cat > test.py <<-EOF
	wait_for_motion(mask="$testdir/videotestsrc-mask-video.png")
	for motion_result in detect_motion(
	        mask="$testdir/videotestsrc-mask-no-video.png"):
	    if not motion_result:
	        import sys
	        sys.exit(0)
	raise Exception("Timeout occured without any result reported.")
	EOF
    stbt run -v test.py
}

test_detect_motion_changing_mask_is_not_racy() {
    cat > test.py <<-EOF
	for motion_result in detect_motion(
	        mask="$testdir/videotestsrc-mask-video.png"):
	    if not motion_result:
	        raise Exception("Motion not reported.")
	    # Leave time for another frame to be processed with this mask
	    import time
	    time.sleep(1.0) # make sure the test fail (0.1s also works)
	    break
	for motion_result in detect_motion(
	        mask="$testdir/videotestsrc-mask-no-video.png"):
	    # Not supposed to detect motion
	    if not motion_result:
	        import sys
	        sys.exit(0)
	    else:
	        raise Exception("Wrongly reported motion: race condition.")
	raise Exception("Timeout occured without any result reported.")
	EOF
    stbt run -v test.py
}

test_detect_motion_example_press_and_wait_for_no_motion() {
    cat > test.py <<-EOF
	key_sent = False
	for motion_result in detect_motion():
	    if not key_sent:
	        if not motion_result:
	            raise Exception("Motion not reported.")
	        press("checkers-8")
	        key_sent = True
	    else:
	        if not motion_result:
	            import sys
	            sys.exit(0)
	raise Exception("Timeout occured without any result reported.")
	EOF
    stbt run -v test.py
}

test_detect_motion_visualisation() {
    cat > detect_motion.py <<-EOF &&
	for result in detect_motion():
	    pass
	EOF
    mkfifo fifo || fail "Initial test setup failed"

    stbt run -v \
        --source-pipeline "multifilesrc location=$testdir/box-%05d.png loop=true" \
        --sink-pipeline 'gdppay ! filesink location=fifo' \
        detect_motion.py &
    source_pid=$!
    trap "kill $source_pid; rm fifo" EXIT

    cat > verify.py <<-EOF &&
	wait_for_match("$testdir/motion-visualisation.png")
	EOF
    stbt run -v --control none \
        --source-pipeline 'filesrc location=fifo ! gdpdepay' \
        verify.py
}
