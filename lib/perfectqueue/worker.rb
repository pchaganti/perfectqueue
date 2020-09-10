#
# PerfectQueue
#
# Copyright (C) 2012-2013 Sadayuki Furuhashi
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

module PerfectQueue

  class Worker
    def self.run(runner, config=nil, &block)
      new(runner, config, &block).run
    end

    def initialize(runner, config=nil, &block)
      block = Proc.new { config } if config
      config = block.call

      @config = config
      @log = config[:logger] || Logger.new(STDERR)
      @runner = runner

      @detach_wait = config[:detach_wait] || config['detach_wait'] || 10.0

      @sv = Supervisor.new(runner, &block)
      @detach = false
      @finish_flag = BlockingFlag.new
    end

    def run
      @pid = fork do
        $0 = "perfectqueue-supervisor:#{@runner}"
        @sv.run
        exit! 0
      end

      install_signal_handlers

      begin

        until @finish_flag.set?
          pid, status = Process.waitpid2(@pid, Process::WNOHANG)
          break if pid
          @finish_flag.wait(1)
        end

        return if pid

        if @detach
          wait_time = Time.now + @detach_wait
          while (w = wait_time - Time.now) > 0
            sleep [0.5, w].min
            pid, status = Process.waitpid2(@pid, Process::WNOHANG)
            break if pid
          end

        else
          # child process finished unexpectedly
          @log.info "Child process finished unexpectedly pid=#{pid}"
        end

      rescue Errno::ECHILD => e
        @log.info "#{e.class}: #{e.message}\n#{e.backtrace}"
      end
    end

    def stop(immediate)
      send_signal(immediate ? :QUIT : :TERM)
    end

    def restart(immediate)
      send_signal(immediate ? :HUP : :USR1)
    end

    def logrotated
      send_signal(:USR2)
    end

    def detach
      send_signal(:INT)
      @detach = true
      @finish_flag.set!
    end

    private
    def send_signal(sig)
      begin
        Process.kill(sig, @pid)
      rescue Errno::ESRCH, Errno::EPERM
      end
    end

    def install_signal_handlers
      s = self
      SignalThread.new do |st|
        st.trap :TERM do
          s.stop(false)
        end

        # override
        st.trap :INT do
          s.detach
        end

        st.trap :QUIT do
          s.stop(true)
        end

        st.trap :USR1 do
          s.restart(false)
        end

        st.trap :HUP do
          s.restart(true)
        end

        st.trap :USR2 do
          s.logrotated
        end
      end
    end
  end

end
