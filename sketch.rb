#!/usr/bin/env ruby

$LOAD_PATH << 'lib'

require "pathname"
require "tempfile"
require "optparse"
require "logger"

require "owonosc.rb"


Pathname("./20140128_21011390910890_433.bin").open do |f|
	OWONOSC.read_vector(f) do |c|
		p c
		p c.data[1..1000]
	end
end
