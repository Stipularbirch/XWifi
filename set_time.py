import datetime

def _win_set_time(time_tuple):
	import pywin32
    
	dayOfWeek = datetime.datetime(time_tuple).isocalendar()[2]
	pywin32.SetSystemTime( time_tuple[:2] + (dayOfWeek,) + time_tuple[2:])


def _linux_set_time(time_tuple):
	import ctypes, ctypes.util, time
	CLOCK_REALTIME = 0

	class timespec(ctypes.Structure):
		_fields_ = [("tv_sec", ctypes.c_long),
                    ("tv_nsec", ctypes.c_long)]

	librt = ctypes.CDLL(ctypes.util.find_library("rt"))

	ts = timespec()
	ts.tv_sec = int( time.mktime( datetime.datetime( *time_tuple[:6]).timetuple() ) )
	ts.tv_nsec = time_tuple[6] * 1000000 # Millisecond to nanosecond

	librt.clock_settime(CLOCK_REALTIME, ctypes.byref(ts))
