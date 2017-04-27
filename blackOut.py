#!/usr/bin/python
#Developed by Malay on 07-20-2015. 
# Purpose of this program is to read status.txt file to get server details along with outage start and end time. Then this will insert rows to backup tables(events_bkp and outages_bkp) before deleteing rows from original tables.
from Crypto.Cipher import AES
import base64
import psycopg2
pwd="gUhd9TxpnQppnZVAf7cv9mzEEUFR9TH3TL7h06pzaGU=".rjust(32) # for ebi_write
#pwd = "gUhd9TxpnQppnZVAf7cv9hnYnk/QLtRBTB/NM86IGfQ=" # for ebi_read
secret_key = '1234567890123456' # create new & store somewhere safe
cipher = AES.new(secret_key,AES.MODE_ECB) # never use ECB in strong systems obviously
decoded = cipher.decrypt(base64.b64decode(pwd))
count=0
name = raw_input("Enter file:")
if len(name) < 1 : name = "status.txt"
handle = open(name,'r')
for line in handle:
	print "----",count,"***",line
	#global nodelabel
	#global start
	#global end
	if count==1:
		words=line.split(',')
		#global nodelabel
		#global start
		#global end
		nodelabel=words[0].strip()
		start=words[1].strip()
		end=words[2].strip()
		print "-----nodelabel",nodelabel,"start***",start,"end***",end
	count=count+1	
nodeids = list()
svclosteventid = list()
ifregainedservice = list()
iflostservice = list()
servicename = list()
#conn = psycopg2.connect(database="opennms", user="ebi_read", password=decoded, host="10.13.195.68", port="5432")
conn = psycopg2.connect(database="opennms", user="xxx", password=decoded, host="xxx", port="5432")

print "Opened database successfully"
print "**************",nodelabel,start,end

def getNode(conn):
	global nodeid
	cur = conn.cursor()
	sql = "SELECT nodeid from node where nodelabel=%s"
	cur.execute(sql%(nodelabel));
	rows = cur.fetchall()
	for row in rows:
   		nodeid =  row[0]
		print nodeid
getNode(conn)
print "NodeId:",nodeid;
print "**************",nodelabel,start,end
#GETTING OUTAGE DETAILS
def getOutage(nodeid):
	global nodeids
	global svclosteventid
	global ifregainedservice
	global iflostservice
	global servicename
	i=0
	cur1 = conn.cursor()
	sql1 = "select outages.nodeid,outages.svclosteventid,outages.ifregainedservice,outages.iflostservice,service.servicename from outages join events on events.eventid = outages.svclosteventid JOIN service ON (outages.serviceid=service.serviceid) where events.eventuei = 'uei.opennms.org/nodes/nodeLostService' and outages.nodeid=%s AND (iflostservice, ifregainedservice) OVERLAPS (%s::TIMESTAMP,%s::TIMESTAMP+ '86400'::INTERVAL)"
	cur1.execute(sql1,(nodeid,start,end));
	rows1 = cur1.fetchall()
	for row1 in rows1:
		
		nodeids.append(row1[0])
		svclosteventid.append(row1[1])
		ifregainedservice.append(row1[2])
		iflostservice.append(row1[3])
		servicename.append(row1[4])
		print "********",servicename[i]
		i=i+1
getOutage(nodeid)
print "svclosteventid",svclosteventid,"servicename",servicename,"iflostservice:",iflostservice,"ifregainedservice:",ifregainedservice,"nodeid:",nodeids	
#INSERTING EVENTS AND OUTAGES ROWS INTO BACKUP TABLES
def insert(svclosteventid):
	svclei=svclosteventid[0]
	print "################",svclei
	sqlinsertevent = "insert into events_bkp select * from events where eventid=%s"
	sqlinsertoutage = "insert into outages_bkp select * from outages where svclosteventid=%s"
	cureventinsert = conn.cursor()
	cureventinsert.execute(sqlinsertevent,(svclei,));
	conn.commit()
	curoutageinsert = conn.cursor()
	curoutageinsert.execute(sqlinsertoutage,(svclei,));
	conn.commit()
insert(svclosteventid)
#DELETE OUTAGES ROWS FROM EVENTS AND OUTAGES TABLES
def delete(svclosteventid):
	svclei=svclosteventid[0]
	sqldeloutage = "delete from outages where svclosteventid=%s"
	sqldelevent = "delete from events where eventid=%s"
	cureventdel = conn.cursor()
	cureventdel.execute(sqldelevent,(svclei,));
	conn.commit()
	curoutagedel = conn.cursor()
	curoutagedel.execute(sqldeloutage,(svclei,));
	conn.commit()
delete(svclosteventid)
conn.close()
