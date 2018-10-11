-------------------------------------------------------------------
-- Copyright (c) 2009-2012 Oracle USA and John Beresniewicz
-- NOTE: execution of this script requires Diagnostic Pack license
--
-- Returns sampled events from V$ACTIVE_SESSION_HISTORY whose time_waited
-- exceeds a given significance level as determined using V$EVENT_HISTOGRAM
-- as follows:
--
-- 1) Each histogram time_waited bucket is assigned a significance using:
-- BUCKET_SIGNIFICANCE = SUM(wait count in this and higher buckets)
--                       / SUM(wait count for all buckets)
--
-- 2) Join to V$ACTIVE_SESSION_HISTORY by time_waited to assign significance
-- to events and filter for events with significance > :siglevel (input variable)
--
-- Useful filter values:   0.99 <= :siglevel < 1.0
-- (higher values filter out more events)
-------------------------------------------------------------------
WITH EH$stats
as
(select 
       EH.*
      ,ROUND(1 - (tot_count - bucket_tot_count + wait_count) / tot_count,6)   as event_bucket_siglevel
from
    (select event#
            ,event
            ,wait_time_milli
            ,wait_count
            ,ROUND(LOG(2,wait_time_milli))              as event_bucket
            ,SUM(wait_count) OVER (PARTITION BY event#) as tot_count
            ,SUM(wait_count) OVER (PARTITION BY event# ORDER BY wait_time_milli RANGE UNBOUNDED PRECEDING)
                                                        as bucket_tot_count
       from  v$event_histogram
     ) EH
)
select
      EH.event_bucket
     ,ASH.sample_id
     ,ASH.session_id
     ,EH.event_bucket_siglevel as bucket_siglevel
     ,ASH.event
     ,ROUND(ASH.time_waited/1000) ASH_time_waited_milli
     ,ASH.sql_id
 from 
       EH$stats  EH
      ,v$active_session_history ASH
 where
      EH.event# = ASH.event#
  and EH.event_bucket_siglevel > :siglevel
  and EH.event_bucket = CASE ASH.time_waited WHEN 0 THEN null 
                                             ELSE TRUNC(LOG(2,ASH.time_waited/1000))+1 END
order by 
sample_id, event, session_id
;
