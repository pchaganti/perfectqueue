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
  module Application

    module RouterDSL
      def route(options)
        patterns = options.keys.select {|k| !k.is_a?(Symbol) }
        klasses = patterns.map {|k| options.delete(k) }
        patterns.zip(klasses).each {|pattern,sym|
          add_route(pattern, sym, options)
        }
        nil
      end

      def add_route(pattern, klass, options)
        router.add(pattern, klass, options)
      end

      def router=(router)
        (class<<self;self;end).instance_eval do
          self.__send__(:define_method, :router) { router }
        end
        router
      end

      def router
        self.router = Router.new
      end
    end

    class Router
      def initialize
        @patterns = []
        @cache = {}
      end

      def add(pattern, sym, options={})
        case pattern
        when Regexp
          # ok
        when String, Symbol
          pattern = /\A#{Regexp.escape(pattern)}\z/
        else
          raise ArgumentError, "pattern should be String or Regexp but got #{pattern.class}: #{pattern.inspect}"
        end

        @patterns << [pattern, sym]
      end

      def route(type)
        if @cache.has_key?(type)
          return @cache[type]
        end

        @patterns.each {|(pattern,sym)|
          if pattern.match(type)
            base = resolve_application_base(sym)
            return @cache[type] = base
          end
        }
        return @cache[type] = nil
      end
      attr_reader :patterns

      private
      def resolve_application_base(sym)
        case sym
        when Symbol
          self.class.const_get(sym)
        else
          sym
        end
      end
    end

  end
end

