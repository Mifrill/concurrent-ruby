require 'spec_helper'
require_relative 'runnable_shared'

module Concurrent

  describe TimerTask do

    after(:each) do
      @subject = @subject.runner if @subject.respond_to?(:runner)
      @subject.kill unless @subject.nil?
      @thread.kill unless @thread.nil?
      sleep(0.1)
    end

    context ':runnable' do

      subject { TimerTask.new{ nil } }

      it_should_behave_like :runnable
    end

    context 'created with #new' do

      context '#initialize' do

        it 'raises an exception if no block given' do
          lambda {
            @subject = Concurrent::TimerTask.new
          }.should raise_error
        end

        it 'uses the default execution interval when no interval is given' do
          @subject = TimerTask.new{ nil }
          @subject.execution_interval.should eq TimerTask::EXECUTION_INTERVAL
        end

        it 'uses the default timeout interval when no interval is given' do
          @subject = TimerTask.new{ nil }
          @subject.timeout_interval.should eq TimerTask::TIMEOUT_INTERVAL
        end

        it 'uses the given execution interval' do
          @subject = TimerTask.new(execution_interval: 5){ nil }
          @subject.execution_interval.should eq 5
        end

        it 'uses the given timeout interval' do
          @subject = TimerTask.new(timeout_interval: 5){ nil }
          @subject.timeout_interval.should eq 5
        end
      end

      context '#kill' do
        pending
      end
    end

    context 'created with TimerTask.run!' do

      context 'arguments' do

        it 'raises an exception if no block given' do
          lambda {
            @subject = Concurrent::TimerTask.run
          }.should raise_error
        end

        it 'passes the options to the new TimerTask' do
          opts = {
            execution_interval: 100,
            timeout_interval: 100,
            run_now: false,
            logger: proc{ nil },
            block_args: %w[one two three]
          }
          @subject = TimerTask.new(opts){ nil }
          TimerTask.should_receive(:new).with(opts).and_return(@subject)
          Concurrent::TimerTask.run!(opts)
        end

        it 'passes the block to the new TimerTask' do
          @expected = false
          block = proc{ @expected = true }
          @subject = TimerTask.run!(run_now: true, &block)
          sleep(0.1)
          @expected.should be_true
        end

        it 'creates a new thread' do
          thread = Thread.new{ sleep(1) }
          Thread.should_receive(:new).with(any_args()).and_return(thread)
          @subject = TimerTask.run!{ nil }
        end
      end
    end

    context 'execution' do

      it 'runs the block immediately when the :run_now option is true' do
        @expected = false
        @subject = TimerTask.run!(execution: 500, now: true){ @expected = true }
        sleep(0.1)
        @expected.should be_true
      end

      it 'waits for :execution_interval seconds when the :run_now option is false' do
        @expected = false
        @subject = TimerTask.run!(execution: 0.5, now: false){ @expected = true }
        @expected.should be_false
        sleep(1)
        @expected.should be_true
      end

      it 'waits for :execution_interval seconds when the :run_now option is not given' do
        @expected = false
        @subject = TimerTask.run!(execution: 0.5){ @expected = true }
        @expected.should be_false
        sleep(1)
        @expected.should be_true
      end

      it 'yields to the execution block' do
        @expected = false
        @subject = TimerTask.run!(execution: 1){ @expected = true }
        sleep(2)
        @expected.should be_true
      end

      it 'passes any given arguments to the execution block' do
        args = [1,2,3,4]
        @expected = nil
        @subject = TimerTask.new(execution_interval: 0.5, args: args) do |*args|
          @expected = args
        end
        @thread = Thread.new { @subject.run }
        sleep(1)
        @expected.should eq args
      end

      it 'kills the worker thread if the timeout is reached' do
        # the after(:each) block will trigger this expectation
        Thread.should_receive(:kill).at_least(1).with(any_args())
        @subject = TimerTask.new(execution_interval: 0.5, timeout_interval: 0.5){ Thread.stop }
        @thread = Thread.new { @subject.run }
        sleep(1.5)
      end
    end

    context 'observation' do

      let(:observer) do
        Class.new do
          attr_reader :time
          attr_reader :value
          attr_reader :ex
          define_method(:update) do |time, value, ex|
            @time = time
            @value = value
            @ex = ex
          end
        end.new
      end

      it 'notifies all observers on success' do
        task = TimerTask.new(run_now: true){ sleep(0.1); 42 }
        task.add_observer(observer)
        Thread.new{ task.run }
        sleep(1)
        observer.value.should == 42
        observer.ex.should be_nil
        task.kill
      end

      it 'notifies all observers on timeout' do
        task = TimerTask.new(run_now: true, timeout: 1){ sleep }
        task.add_observer(observer)
        Thread.new{ task.run }
        sleep(2)
        observer.value.should be_nil
        observer.ex.should be_a(Concurrent::TimeoutError)
        task.kill
      end

      it 'notifies all observers on error' do
        task = TimerTask.new(run_now: true){ sleep(0.1); raise ArgumentError }
        task.add_observer(observer)
        Thread.new{ task.run }
        sleep(1)
        observer.value.should be_nil
        observer.ex.should be_a(ArgumentError)
        task.kill
      end
    end
  end
end
