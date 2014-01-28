require 'socket'

class OWONOSC
	RESPONSE_START_LENGTH = 12
	BMP_FILE_FLAG = 1

	# vector data
	STARTBIN = "STARTBIN"
	# bitmap data
	STARTBMP = "STARTBMP"
	# deep memory vector data
	STARTMEMDEPTH = "STARTMEMDEPTH"

	CH_VV = [
		0.002,
		0.005,
		0.01,
		0.02,
		0.05,
		0.1,
		0.2,
		0.5,
		1,
		2,
		5,
		10,
		20,
		50,
		100,
		200,
		500,
		1000,
		2000,
		5000,
		10000,
	]

	class ChannelData
		attr_accessor :name
		attr_accessor :is_deep
		attr_accessor :length
		attr_accessor :flags
		attr_accessor :offset
		attr_accessor :whole_points
		attr_accessor :points
		attr_accessor :slow_moving_number
		attr_accessor :time_base_level
		attr_accessor :zero_point
		attr_accessor :voltage_level
		attr_accessor :power_index
		attr_accessor :spacing_interval
		attr_accessor :frequency
		attr_accessor :cycles
		attr_accessor :voltage_value
		attr_accessor :data

		def deep?
			@is_deep
		end

		def inspect
			hash = {}
			instance_variables.each do |v|
				if v == :@data
					hash[:@data] = "...."
				else
					hash[v] = instance_variable_get(v)
				end
			end
			"#<%s:%x %p>" % [self.class.name, object_id, hash]
		end
	end

	def initialize(host, port)
		@host = host
		@port = port
	end

	def read(start_command, &block)
		sock = TCPSocket.open(@host, @port)
		begin
			sock.write(start_command)
			length, _, flag = *sock.read(RESPONSE_START_LENGTH).unpack("V3")
			parts = flag >= 128 ? flag - 128 : 1
			part  = 1

			got = 0
			while got < length
				buffer = sock.readpartial(1024)
				got += buffer.size
				yield buffer, got, length, part, parts
			end

			while part < parts
				length, _, flag = *sock.read(RESPONSE_START_LENGTH).unpack("V3")
				got = 0
				while got < length
					@sock.readpartial(4096, buffer)
					got += buffer.size
					yield buffer, got, length, part, parts
				end
				part += 1
			end
		ensure
			sock.close
		end
	end

	def self.read_vector(io, &block)
		## See detail: https://github.com/bjonnh/owon-sds7102-protocol/blob/master/parse.c

		## header
		# 6 bytes (ASCII): file header
		# 4 bytes (int): file length. negative value -> customized and use absolute value

		model = io.read(6)
		size = io.read(4).unpack("V").pack("l").unpack("l")[0]

		# not in spec...
		serial = io.read(30)
		triggerstatus = io.read(1)
		io.read(13) # unknown

		## channel data
		# 3 bytes (ASCII): name of waveform
		# 4 bytes (int): length of this channel. negative value -> deep memory
		# -> 4 bytes (int): flags (0: 0=normal or 1=deep, 1: 0=no deep, 1=have deep) (negative length only)
		# -> 4 bytes (int): offset (SDS series only)
		# 4 bytes (int): whole screen collecting points
		# 4 bytes (int): number of collecting points
		# 4 bytes (int): slow moving number
		# 4 bytes (int): time base level
		# 4 bytes (int): zero point
		# 4 bytes (int): voltage level
		# 4 bytes (int): attenuation mutiplying power index
		# 4 bytes (float): spacing interval of the describal point (uS)
		# 4 bytes (int): frequency
		# 4 bytes (int): cycle (uS)
		# 4 bytes (float): voltage value per point (mV)
		# short[] (normal) or bytes[] (deep)
		# ... array of length of (number of collecting point) 

		while io.read(3) =~ /CH\d/
			channel = ChannelData.new
			channel.name = Regexp.last_match[0]
			channel.is_deep = false
			channel.length = io.read(4).unpack("V").pack("l").unpack("l")[0]
			if channel.length < 0
				channel.flags = io.read(4).unpack("V")[0]
				channel.is_deep = channel.flags[0] == 1
				channel.length = -channel.length
			end
			if model =~ /SPBS/
				channel.offset = io.read(4).unpack("V").pack("l").unpack("l")[0]
			end
			channel.whole_points       = io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.points             = io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.slow_moving_number = io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.time_base_level    = io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.zero_point         = io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.voltage_level      = CH_VV[io.read(4).unpack("V").pack("l").unpack("l")[0]]
			channel.power_index        = 10 ** io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.spacing_interval   = io.read(4).unpack("e")[0]
			channel.frequency          = io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.cycles             = io.read(4).unpack("V").pack("l").unpack("l")[0]
			channel.voltage_value      = io.read(4).unpack("e")[0]
			
			if channel.is_deep
				channel.data = io.read(channel.points).unpack("C*")
			else
				channel.data = io.read(channel.points * 2).unpack("n*").map {|n|
					(n[15] == 1 ? -( (n ^ 0xffff) + 1) : n) * 2.0 * channel.voltage_value * channel.voltage_level / channel.power_index
				}
			end

			yield channel
		end

	end
end



