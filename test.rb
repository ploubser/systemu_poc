#!/bin/env ruby
require 'rubygems'
require 'systemu'
require 'pp'

# Fake shell
class Shell
  attr_accessor :status

  def initialize(cmd)
    @status = nil
    @cmd = cmd
    @opts = {"env" => {"LC_ALL" => "C"},
             "stdout" => "",
             "stderr" => "",
             "stdin" => nil,
             "cwd" => Dir.tmpdir}
  end

  def runcommand
     @status = systemu(@cmd, @opts)
  end
end



@result = nil

# simulates the runner loop
def runner
  # This thread simulates the agent
  tr = Thread.new do
    shell = Shell.new("ruby -e '10000000.times{}'")
    shell.runcommand

    @result = shell.status
  end

  # Here we kill the thread, simulating a timed out agent
  sleep 0.2
  tr.kill!
end

# -----------Test 1------------
# Test one has no gaurd, meaning that when the thread is killed
# we will be left with a defunct process and @result being nil
puts "starting test 1"
runner
sleep 1
puts "The value of @shell.status = #{@result.inspect}"
puts "Check the proctable, there should be 1 zombie"
puts "hit enter for the next test"
gets
# -----------End of Test 1------------

# Now we fix runcommand to deal with zombies

class Shell
  def runcommand
    thread = Thread.current
    @status = systemu(@cmd, @opts) do |cid|
      begin
        # guard the process. if the thread which is going
        # to reap is still alive, we wait.
        while(thread.alive?)
          sleep 0.1
        end

        # Caller thread is dead. Check is the child
        # spawned by systemu is still alive. if it is,
        # we do a blocking waitpid.
        Process.waitpid(cid) if Process.getpgid(cid)

      rescue SystemExit
      rescue Errno::ESRCH
      rescue Errno::ECHILD
      end
    end
  end
end



# -----------Test 2------------
puts "Starting test 2"
@result = nil

runner
# When the guard thread is done we're sure that there isn't a zombie left over from
# the thread dying because it was reaped by waitpid. Doing nothing while the thread is
# alive also avoids the race condition introduced by the last commit.
#
# But now we're fucked. The "agent" thread that was suppose to do something
# with the exit code is dead. Shell.status is nil and there is nothing we can do about it.
puts "The value of @shell.status = #{@result.inspect}"
puts "Check the proctable, there should still only be 1 zombie left over from the previous test"
puts "hit enter for next test"
gets

# The other reason there could be a nil is if the pipe between the two systemu
# processes break, from the 2nd process dying or something similar. If we default
# the @status variable to -1 instead of nil we should be able to handle this normally.


# -----------Test 2------------


# -----------Test 3------------
# This is a simulation of why the old code would return the wrong
# exit code. Anything that takes longer than a second will have a
# waitpid setup for it by the guard thread, which will reap it.

class Shell
  def runcommand
    @status = systemu(@cmd, @opts) do |cid|
      begin
        sleep 1
        Process.waitpid(cid)

      rescue SystemExit
      rescue Errno::ESRCH
      rescue Errno::ECHILD
      end
    end
  end
end

puts "Starting test three"
puts "ruby -e 'sleep 1.1;exit 1' - Expecting exitcode 1"
shell = Shell.new("ruby -e 'sleep 1.1;exit 1'")
shell.runcommand
puts "Exit code is #{shell.status}"

