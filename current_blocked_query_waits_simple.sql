select session_id, 
	wait_duration_ms / 1000. / 60. as wait_duration_min,
	wait_type,
	blocking_session_id
from sys.dm_os_waiting_tasks
where blocking_session_id is not null;
GO