# import os
# import select
# import sys
# import signal
# import errno
# import fcntl
# import termios


# def flush_pts(fd):
#     """
#     Attempt to flush/poke the pseudo terminal to trigger output.
#     """
#     try:
#         # Method 1: Send TIOCFLUSH ioctl to flush buffers
#         try:
#             # fcntl.ioctl(fd, 16, 0)
#             termios.tcflush(fd, 0)
#             termios.tcflush(fd, 1)
#             termios.tcflush(fd, 2)
#             termios.tcsendbreak(fd, 0)
#             print("Flushed terminal buffers")
#         except OSError:
#             pass

#         try:
#             termios.tcgetattr(fd)
#             termios.tcsetattr()
#             print("Got terminal attributes")
#         except OSError:
#             pass

#         try:
#             # This sometimes triggers programs to flush their output
#             winsize = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\x00" * 8)
#             fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
#             print("Triggered window size check")
#         except OSError:
#             pass

#     except Exception as e:
#         print(f"Note: Could not flush terminal: {e}")


# def read_from_pts(pts_path="/dev/pts/0"):
#     """
#     Read from a pseudo terminal device.

#     Args:
#         pts_path (str): Path to the pseudo terminal device
#     """
#     try:
#         # Open the pseudo terminal for reading
#         # Try both read-only and read-write modes
#         try:
#             fd = os.open(pts_path, os.O_RDWR | os.O_NONBLOCK)
#             print(f"Successfully opened {pts_path} (read-write mode)")
#         except OSError:
#             fd = os.open(pts_path, os.O_RDONLY | os.O_NONBLOCK)
#             print(f"Successfully opened {pts_path} (read-only mode)")

#         # Try to flush/poke the terminal
#         flush_pts(fd)

#         print("Reading from pseudo terminal... (Press Ctrl+C to stop)")

#         # Give it a moment after flushing
#         import time

#         time.sleep(0.1)

#         consecutive_empty_reads = 0
#         max_empty_reads = 10

#         while True:
#             try:
#                 # Use select to check if data is available
#                 ready, _, _ = select.select([fd], [], [], 1.0)

#                 if ready:
#                     # Read available data
#                     data = os.read(fd, 1024)
#                     if data:
#                         consecutive_empty_reads = 0
#                         # Decode and print the data
#                         try:
#                             decoded = data.decode("utf-8")
#                             print(f"Received: {repr(decoded)}")
#                             # If you want to print the actual content:
#                             # print(decoded, end='')
#                         except UnicodeDecodeError:
#                             print(f"Received (raw bytes): {data}")
#                     else:
#                         consecutive_empty_reads += 1
#                         if consecutive_empty_reads >= max_empty_reads:
#                             print("Multiple empty reads")
#                             break
#                 else:
#                     consecutive_empty_reads += 1
#                     if consecutive_empty_reads % 5 == 0:
#                         print(
#                             f"No data for {consecutive_empty_reads} cycles."
#                         )
#                         flush_pts(fd)
#                     else:
#                         print(".", end="", flush=True)

#             except OSError as e:
#                 if e.errno == errno.EAGAIN or e.errno == errno.EWOULDBLOCK:
#                     # No data available right now, continue
#                     continue
#                 else:
#                     print(f"Error reading from {pts_path}: {e}")
#                     break

#     except FileNotFoundError:
#         print(f"Error: {pts_path} not found")
#         return 1
#     except PermissionError:
#         print(f"Error: Permission denied to access {pts_path}")
#         print("Try running with sudo or check permissions")
#         return 1
#     except OSError as e:
#         print(f"Error opening {pts_path}: {e}")
#         return 1
#     except KeyboardInterrupt:
#         print("\nInterrupted by user")
#     finally:
#         try:
#             os.close(fd)
#             print(f"Closed {pts_path}")
#         except Exception:
#             pass

#     return 0


# def signal_handler(signum, frame):
#     """Handle Ctrl+C gracefully"""
#     print("\nReceived interrupt signal, cleaning up...")
#     sys.exit(0)


# if __name__ == "__main__":
#     # Set up signal handler for graceful shutdown
#     signal.signal(signal.SIGINT, signal_handler)

#     # You can specify a different pts path as command line argument
#     pts_path = "/dev/pts/0"
#     if len(sys.argv) > 1:
#         pts_path = sys.argv[1]

#     print(f"Attempting to read from: {pts_path}")
#     exit_code = read_from_pts(pts_path)
#     sys.exit(exit_code)

# import os
# import sys
# import time
# import subprocess
# import fcntl
# import termios


# def method1_write_to_pts(pts_path="/dev/pts/0"):
#     """
#     Method 1: Write to the PTS to trigger output from the process
#     """
#     try:
#         # Open for writing to send commands/signals
#         with open(pts_path, "w") as pts_write:
#             # Send a newline or other trigger
#             pts_write.write("\n")
#             pts_write.flush()
#             print(f"Sent newline to {pts_path}")

#         # Now try to read
#         with open(pts_path, "r") as pts_read:
#             # Set non-blocking
#             fd = pts_read.fileno()
#             flags = fcntl.fcntl(fd, fcntl.F_GETFL)
#             fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

#             print("Reading after poke...")
#             for i in range(10):  # Try reading for a few seconds
#                 try:
#                     data = pts_read.read(1024)
#                     if data:
#                         print(f"Read: {repr(data)}")
#                     else:
#                         print(".", end="", flush=True)
#                 except Exception:
#                     print(".", end="", flush=True)
#                 time.sleep(0.1)

#     except Exception as e:
#         print(f"Method 1 failed: {e}")


# def method2_send_signal_to_session(pts_path="/dev/pts/0"):
#     """
#     Method 2: Send signals to processes using this PTS
#     """
#     try:
#         # Extract PTS number
#         pts_num = pts_path.split("/")[-1]

#         # Find processes using this PTS
#         result = subprocess.run(
#             ["ps", "-t", pts_num, "-o", "pid,cmd"],
#             capture_output=True, text=True
#         )

#         if result.returncode == 0:
#             lines = result.stdout.strip().split("\n")[1:]  # Skip header
#             for line in lines:
#                 if line.strip():
#                     pid = line.split()[0]
#                     print(f"Found process {pid} on {pts_path}")

#                     try:
#                         os.kill(int(pid), 28)  # SIGWINCH
#                         print(f"Sent SIGWINCH to {pid}")
#                     except Exception:
#                         pass

#                     # Send SIGCONT to continue if paused
#                     try:
#                         os.kill(int(pid), 18)  # SIGCONT
#                         print(f"Sent SIGCONT to {pid}")
#                     except Exception:
#                         pass

#         # Now try to read
#         time.sleep(0.1)
#         with open(pts_path, "r") as pts_read:
#             fd = pts_read.fileno()
#             flags = fcntl.fcntl(fd, fcntl.F_GETFL)
#             fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

#             for i in range(10):
#                 try:
#                     data = pts_read.read(1024)
#                     if data:
#                         print(f"Read after signal: {repr(data)}")
#                     else:
#                         print(".", end="", flush=True)
#                 except Exception:
#                     print(".", end="", flush=True)
#                 time.sleep(0.1)

#     except Exception as e:
#         print(f"Method 2 failed: {e}")


# def method3_cat_pts(pts_path="/dev/pts/0"):
#     """
#     Method 3: Use external tools to poke the PTS
#     """
#     try:
#         # Method 3a: Use 'cat' with timeout to read
#         print("Trying with timeout + cat...")
#         result = subprocess.run(
#             ["timeout", "2", "cat", pts_path], capture_output=True, text=True
#         )
#         if result.stdout:
#             print(f"Cat read: {repr(result.stdout)}")
#         else:
#             print("Cat read nothing")

#         # Method 3b: Use 'dd' to read a specific amount
#         print("Trying with dd...")
#         result = subprocess.run(
#             ["dd", f"if={pts_path}", "bs=1024", "count=1", "iflag=nonblock"],
#             capture_output=True,
#             text=True,
#             timeout=1,
#         )
#         if result.stdout:
#             print(f"DD read: {repr(result.stdout)}")
#         else:
#             print("DD read nothing")

#     except Exception as e:
#         print(f"Method 3 failed: {e}")


# def method4_direct_ioctl_poke(pts_path="/dev/pts/0"):
#     """
#     Method 4: Direct ioctl manipulation
#     """
#     try:
#         fd = os.open(pts_path, os.O_RDWR | os.O_NONBLOCK)

#         # Try various ioctl calls to wake up the terminal
#         try:
#             # TIOCFLUSH - flush input and output
#             fcntl.ioctl(fd, termios.TIOCFLUSH, 2)  # FWRITE
#             print("Flushed output")
#         except Exception:
#             pass

#         try:
#             # TIOCSTART - start output
#             fcntl.ioctl(fd, termios.TIOCSTART, 0)
#             print("Started output")
#         except Exception:
#             pass

#         try:
#             # Send break signal
#             termios.tcsendbreak(fd, 0)
#             print("Sent break")
#         except Exception:
#             pass

#         # Try to read after poking
#         time.sleep(0.1)
#         for i in range(10):
#             try:
#                 data = os.read(fd, 1024)
#                 if data:
#                     print(
#                         "Read after ioctl: "
#                         f"{repr(data.decode('utf-8', errors='ignore'))}"
#                     )
#                 else:
#                     print(".", end="", flush=True)
#             except Exception:
#                 print(".", end="", flush=True)
#             time.sleep(0.1)

#         os.close(fd)

#     except Exception as e:
#         print(f"Method 4 failed: {e}")


# if __name__ == "__main__":
#     pts_path = "/dev/pts/0"
#     if len(sys.argv) > 1:
#         pts_path = sys.argv[1]

#     print(f"Trying different methods to poke {pts_path}...")

#     print("\n=== Method 1: Write to PTS ===")
#     method1_write_to_pts(pts_path)

#     print("\n=== Method 2: Send signals to processes ===")
#     method2_send_signal_to_session(pts_path)

#     print("\n=== Method 3: External tools ===")
#     method3_cat_pts(pts_path)

#     print("\n=== Method 4: Direct ioctl ===")
#     method4_direct_ioctl_poke(pts_path)

# import os
# import select
# import sys
# import signal
# import errno
# import termios
# import tty
# import time


# def set_terminal_mode(fd, mode="raw"):
#     """
#     Set the terminal to different modes.

#     Args:
#         fd: File descriptor of the terminal
#         mode: 'raw', 'cbreak', 'canonical', or 'restore'
#     """
#     try:
#         if mode == "raw":
#             # Raw mode - no input processing, character-by-character
#             tty.setraw(fd)
#             print("Set terminal to RAW mode")

#         elif mode == "cbreak":
#             # Cbreak mode - no line buffering, but some processing
#             tty.setcbreak(fd)
#             print("Set terminal to CBREAK mode")

#         elif mode == "canonical":
#             # Canonical mode - line buffering, full processing
#             attrs = termios.tcgetattr(fd)
#             attrs[3] |= termios.ICANON | termios.ECHO
#             termios.tcsetattr(fd, termios.TCSANOW, attrs)
#             print("Set terminal to CANONICAL mode")

#         elif mode == "noncanonical":
#             # Non-canonical mode with custom settings
#             attrs = termios.tcgetattr(fd)
#             # Disable canonical mode
#             attrs[3] &= ~termios.ICANON
#             # Set minimum characters to read (0 = non-blocking)
#             attrs[6][termios.VMIN] = 0
#             # Set timeout (0 = no timeout)
#             attrs[6][termios.VTIME] = 0
#             termios.tcsetattr(fd, termios.TCSANOW, attrs)
#             print("Set terminal to NON-CANONICAL mode")

#         return True

#     except Exception as e:
#         print(f"Failed to set terminal mode '{mode}': {e}")
#         return False


# def show_terminal_attributes(fd):
#     """Display current terminal attributes"""
#     try:
#         attrs = termios.tcgetattr(fd)
#         iflag, oflag, cflag, lflag, ispeed, ospeed, cc = attrs

#         print("Terminal attributes:")
#         print(f"  Input flags (iflag): {iflag:016b}")
#         print(f"  Output flags (oflag): {oflag:016b}")
#         print(f"  Control flags (cflag): {cflag:016b}")
#         print(f"  Local flags (lflag): {lflag:016b}")

#         # Check important flags
#         print("  Important flags:")
#         print(
#             "    ICANON (canonical): "
#             f" {'ON' if lflag & termios.ICANON else 'OFF'}"
#         )
#         print(f"    ECHO: {'ON' if lflag & termios.ECHO else 'OFF'}")
#         print(f"    ISIG (signals): "
#               f"{'ON' if lflag & termios.ISIG else 'OFF'}")
#         print(f"    VMIN: {cc[termios.VMIN]}")
#         print(f"    VTIME: {cc[termios.VTIME]}")

#     except Exception as e:
#         print(f"Could not read terminal attributes: {e}")


# def flush_and_drain(fd):
#     """Comprehensive flush and drain operations"""
#     try:
#         # Flush input buffer
#         termios.tcflush(fd, termios.TCIFLUSH)

#         # Flush output buffer
#         termios.tcflush(fd, termios.TCOFLUSH)

#         # Flush both
#         termios.tcflush(fd, termios.TCIOFLUSH)

#         # Drain output (wait for transmission)
#         termios.tcdrain(fd)

#         print("Flushed and drained terminal buffers")

#     except Exception as e:
#         print(f"Could not flush terminal: {e}")


# def read_from_pts_with_modes(pts_path="/dev/pts/0", mode="raw"):
#     original_attrs = None

#     try:
#         # Try opening in read-write mode first
#         try:
#             fd = os.open(pts_path, os.O_RDWR | os.O_NONBLOCK)
#             print(f"Successfully opened {pts_path} (read-write mode)")
#         except OSError:
#             fd = os.open(pts_path, os.O_RDONLY | os.O_NONBLOCK)
#             print(f"Successfully opened {pts_path} (read-only mode)")

#         # Save original terminal attributes
#         try:
#             original_attrs = termios.tcgetattr(fd)
#             print("Saved original terminal attributes")
#         except Exception:
#             print("Could not save original attributes (not a terminal?)")

#         # Show current attributes
#         show_terminal_attributes(fd)

#         # Set the desired terminal mode
#         if not set_terminal_mode(fd, mode):
#             print(f"Warning: Could not set {mode} "
#                    "mode, continuing anyway...")

#         # Flush buffers
#         flush_and_drain(fd)

#         print(
#             "Reading from pseudo terminal " f"in {mode} mode..."
#             "(Press Ctrl+C to stop)"
#         )

#         # Give it a moment
#         time.sleep(0.1)

#         consecutive_empty_reads = 0
#         max_empty_reads = 20

#         method1_write_to_pts_short(pts_path)
#         while True:
#             try:
#                 # Use select to check if data is available
#                 ready, _, _ = select.select([fd], [], [], 0.5)

#                 if ready:
#                     # Read available data
#                     data = os.read(fd, 1024)
#                     if data:
#                         consecutive_empty_reads = 0
#                         # Decode and print the data
#                         try:
#                             decoded = data.decode("utf-8", errors="ignore")
#                             # Also show as clean text
#                             print(f"Clean text: {decoded}")
#                         except UnicodeDecodeError:
#                             print(f"Received (raw bytes): {data}")
#                     else:
#                         consecutive_empty_reads += 1
#                         if consecutive_empty_reads >= max_empty_reads:
#                             print("Multiple empty reads, terminal"
#                                   "might be closed")
#                             break
#                 else:
#                     # Timeout occurred
#                     consecutive_empty_reads += 1
#                     if consecutive_empty_reads % 10 == 0:
#                         print(f"No data for {consecutive_empty_reads}"
#                               "cycles...")
#                         # Try to re-flush periodically
#                         flush_and_drain(fd)
#                     else:
#                         print(".", end="", flush=True)

#             except OSError as e:
#                 if e.errno == errno.EAGAIN or e.errno == errno.EWOULDBLOCK:
#                     continue
#                 else:
#                     print(f"Error reading from {pts_path}: {e}")
#                     break

#     except FileNotFoundError:
#         print(f"Error: {pts_path} not found")
#         return 1
#     except PermissionError:
#         print(f"Error: Permission denied to access {pts_path}")
#         print("Try running with sudo or check permissions")
#         return 1
#     except OSError as e:
#         print(f"Error opening {pts_path}: {e}")
#         return 1
#     except KeyboardInterrupt:
#         print("\nInterrupted by user")
#     finally:
#         try:
#             # Restore original terminal attributes
#             if original_attrs:
#                 termios.tcsetattr(fd, termios.TCSANOW, original_attrs)
#                 print("Restored original terminal attributes")
#             os.close(fd)
#             print(f"Closed {pts_path}")
#         except Exception:
#             pass

#     return 0


# def test_all_modes(pts_path="/dev/pts/0"):
#     """Test all terminal modes"""
#     modes = ["canonical", "noncanonical", "cbreak", "raw"]

#     for mode in modes:
#         print(f"\n{'='*50}")
#         print(f"Testing {mode.upper()} mode")
#         print(f"{'='*50}")

#         try:
#             fd = os.open(pts_path, os.O_RDWR | os.O_NONBLOCK)
#             original_attrs = termios.tcgetattr(fd)

#             set_terminal_mode(fd, mode)
#             flush_and_drain(fd)

#             print(f"Reading in {mode} mode for 3 seconds...")

#             start_time = time.time()
#             while time.time() - start_time < 3:
#                 ready, _, _ = select.select([fd], [], [], 0.1)
#                 if ready:
#                     data = os.read(fd, 1024)
#                     if data:
#                         decoded = data.decode("utf-8", errors="replace")
#                         print(f"[{mode}] Got: {repr(decoded)}")

#             # Restore and close
#             termios.tcsetattr(fd, termios.TCSANOW, original_attrs)
#             os.close(fd)

#         except Exception as e:
#             print(f"Error testing {mode} mode: {e}")

#         time.sleep(1)  # Brief pause between tests


# def signal_handler(signum, frame):
#     """Handle Ctrl+C gracefully"""
#     print("\nReceived interrupt signal, cleaning up...")
#     sys.exit(0)


# def method1_write_to_pts_short(pts_path="/dev/pts/0"):
#     with open(pts_path, "w") as pts_write:
#         # Send a newline or other trigger
#         pts_write.write("\n")
#         pts_write.flush()
#         print(f"Sent newline to {pts_path}")


# def method1_write_to_pts(pts_path="/dev/pts/0"):
#     """
#     Method 1: Write to the PTS to trigger output from the process
#     """
#     import fcntl
#     try:
#         # Open for writing to send commands/signals
#         with open(pts_path, "w") as pts_write:
#             # Send a newline or other trigger
#             pts_write.write("\n")
#             pts_write.flush()
#             print(f"Sent newline to {pts_path}")

#         # Now try to read
#         with open(pts_path, "r") as pts_read:
#             # Set non-blocking
#             fd = pts_read.fileno()
#             flags = fcntl.fcntl(fd, fcntl.F_GETFL)
#             fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

#             print("Reading after poke...")
#             for i in range(10):  # Try reading for a few seconds
#                 try:
#                     data = pts_read.read(1024)
#                     if data:
#                         print(f"Read: {repr(data)}")
#                     else:
#                         print(".", end="", flush=True)
#                 except Exception:
#                     print(".", end="", flush=True)
#                 time.sleep(0.1)

#     except Exception as e:
#         print(f"Method 1 failed: {e}")


# if __name__ == "__main__":
#     # Set up signal handler for graceful shutdown
#     signal.signal(signal.SIGINT, signal_handler)

#     pts_path = "/dev/pts/0"
#     mode = "raw"

#     if len(sys.argv) > 1:
#         pts_path = sys.argv[1]
#     if len(sys.argv) > 2:
#         mode = sys.argv[2]

#     print("PTS Terminal Mode Reader")
#     print(f"Usage: {sys.argv[0]} [pts_path] [mode] [test_all]")
#     print("Modes: raw, cbreak, canonical, noncanonical")
#     print("Use 'test_all' as mode to test all modes")
#     print()

#     if mode == "test_all":
#         test_all_modes(pts_path)
#     else:
#         print(f"Reading from: {pts_path} in {mode} mode")
#         exit_code = read_from_pts_with_modes(pts_path, mode)
#         sys.exit(exit_code)

import os
import sys


def readpty_once(path):
    import select

    data = bytearray()
    epoll = select.epoll()

    with open(path, "w") as f:
        # Writing a null seems to trigger new output while not being
        # recognized as a newline or similar by the sender.
        f.write("\0")
        f.flush()

    with open(path, "rb") as f:
        os.set_blocking(f.fileno(), False)
        epoll.register(f.fileno(), select.EPOLLIN)
        poll_list = epoll.poll(0.1)
        for _ in poll_list:
            data += f.read()
        epoll.unregister(f.fileno())
        epoll.close()

    return data.decode("utf-8", errors="ignore")


def readpty(path):
    """
    The pty created by Cloud Hypervisor is a bit tricky. It seems to require
    some kind of input to deliver output again. Therefore, we send in a '\0'
    byte before reading (the null byte does not seem to trigger any
    interactions with the pty like a newline would do).
    The reading is done in a loop and we cancel reading when no data is
    returned anymore. Doing so has proven to deliver all the output available
    in the pty.
    """
    # We track how many times we read zero bytes form the pty
    consecutive_zero = 0
    data = ""
    try:
        for _ in range(1000):
            out = readpty_once(path)

            if len(out) == 0:
                consecutive_zero += 1
            else:
                consecutive_zero = 0

            data += out

            if consecutive_zero > 10:
                return data

        return data
    except Exception as exc:
        # NOTE(mikal): dear internet, I see you looking at me with your
        # judging eyes. There's a story behind why we do this. You see, the
        # previous implementation did this:
        #
        # out, err = utils.execute('dd',
        #                          'if=%s' % pty,
        #                          'iflag=nonblock',
        #                          run_as_root=True,
        #                          check_exit_code=False)
        # return out
        #
        # So, it never checked stderr or the return code of the process it
        # ran to read the pty. Doing something better than that has turned
        # out to be unexpectedly hard because there are a surprisingly large
        # variety of errors which appear to be thrown when doing this read.
        #
        # Therefore for now we log the errors, but keep on rolling. Volunteers
        # to help clean this up are welcome and will receive free beverages.
        print(
            'Ignored error while reading from instance console pty: %s', exc
        )
        return ''


if __name__ == "__main__":
    pts_path = "/dev/pts/0"
    if len(sys.argv) > 1:
        pts_path = sys.argv[1]

    print(readpty(pts_path))
