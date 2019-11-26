*//opt/sasinside/DemoData/AIHackathon/AnomalyDetection;

*cas mysession;
*caslib _all_ assign;

/* proc casutil; */
/* 		load file="/opt/sas/viya/config/tmp/sas-studiov/PHM08_ex.csv"  */
/* 		outcaslib="PUBLIC" casout="PHM08_jtb"; */
/* run; */

* read in the data;
data casuser.train casuser.train2;
	set public.PHM08_JTB;
	if engine in (1,22,45,63,86,121,130,158,202) then output casuser.train;
	else output casuser.train2;
run;

proc svdd data=casuser.train;
	input cycle x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14
	x15 x16 x17 x18 x19 x20 x21 x22 x23 x24 / level = interval;
	kernel rbf / bw=mean;
	solver actset /;
	savestate rstore=casuser.svddoutput;
	id _all_;
run;

proc astore;
	score data=public.PHM08_EX
	out=casuser.svddscore
	rstore=casuser.svddoutput;
quit;

data casuser.anomalies;
	set casuser.svddscore;
	if _svddscore_ = 1 then flag = "Anomaly";
	else flag = "Normal";
run;

proc casutil;
	promote incaslib='casuser' casdata='anomalies' outcaslib='casuser' casout='anomalies';
run;


/* Plot SVDD Anomaly Detection results */
ods graphics / antialias=on antialiasmax=5200;
proc sgpanel data=casuser.svddscore;
panelby engine / spacing=5;
needle x=cycle y=_SVDDdistance_ / group=_SVDDScore_ baseline=0.85 transparency=0.5;
refline &threshold /label="SVDD Radius Threshold" lineattrs=(color=black) labelpos=max;
title H=14pt "Anomaly Detection using SVDD";
colaxis label="Engine Cycle";
rowaxis label="SVDD Distance";
footnote H=8pt j=l italic "Anomalies when SVDD_Distance exceeds SVDD_Radius Threshold.";
run;

/* distinct list of engines and cycles identified as 'anomalies' */
data public.svddanomalies (promote=Yes);
	set casuser.svddscore;
	format flag $6.;
	if _SVDDSCORE_ = -1 then flag="Normal";
	else flag = "Anomaly";
run;

/* save state of svdd model */
proc astore;
	download rstore=casuser.svddmodel
	store="/ai2018/anomaly-detection/svddstate.sasast";
quit;

/***************************************************************************************************/
/* Run RPCA workflow */
/***************************************************************************************************/
proc rpca data=public.PHM08_EX method=alm lambdaweight=2 outlowrank=casuser.low outsparse=casuser.sparse;
   id engine cycle;
   input X1-X24;
   svd method=eigen;
   where engine in (1,22,45,53,82,105,167,179);
run;

/* Identify 'anomalies' based on abnormal obs (beyond 3sigma variation) of sparse */
proc means data=casuser.sparse std;
var x1-x24;
output out=std;
run;

proc sql;
	select X1, X2, X3, X4, X5, X6, X7, X8, X9, X10, X11, X12, X13, X14, X15, X16, X17, X18, X19, X20, X21, X22, X23, X24
	into :SX1, :SX2, :SX3, :SX4, :SX5, :SX6, :SX7, :SX8, :SX9, :SX10, :SX11, :SX12, :SX13, :SX14, :SX15, :SX16, :SX17, :SX18, :SX19, :SX20, :SX21, :SX22, :SX23, :SX24
	from work.std
	where _STAT_='STD';
quit;

%let set=3;
%macro ex;
data casuser.rpcaanomalies;
	set casuser.sparse;
	format flag $7.;
	if
	%do i=1 %to 24;
		(X&i > &set*&&SX&i or X&i < -&set*&&SX&i) %if &i < 24 %then %do;
		or %end;
	%end;
		then flag = "Anomaly";
	else flag= "Noise";
run;
%mend;
%ex

/* Plot RPCA Anomaly Detection results */
proc sgpanel data=casuser.rpcaanomalies;
panelby engine / spacing=5;
styleattrs datacontrastcolors=(red grlg) datasymbols=(circlefilled);
scatter x=cycle y=X4 / group=flag transparency=0.5;
title H=14pt "Anomaly Detection using RPCA";
colaxis label="Engine Cycle";
rowaxis label="X4 Value";
keylegend / valueattrs=(size=13pt);
run;

/* distinct list of engines and cycles identified as 'anomalies' */
data public.rpcaanomalies (promote=Yes);
	set casuser.rpcaanomalies;
	where flag = "Anomaly";
run;

/***************************************************************************************************/
/* Run Moving Windows PCA workflow */
/***************************************************************************************************/
%let a1=1;
%let a2=22;
%let a3=63;
%let a4=86;
%let a5=167;
%let var=X4;

data casuser.train1 (keep=cycle E&a1.&var) casuser.train2 (keep=cycle E&a2.&var) casuser.train3 (keep=cycle E&a3.&var)
	casuser.train4 (keep=cycle E&a4.&var) casuser.train5 (keep=cycle E&a5.&var);
set public.phm08_ex;
if engine=&a1 then do; E&a1.&var = &var; output casuser.train1; end;
else if engine=&a2 then do; E&a2.&var = &var; output casuser.train2; end;
else if engine=&a3 then do; E&a3.&var = &var; output casuser.train3; end;
else if engine=&a4 then do; E&a4.&var = &var; output casuser.train4; end;
else if engine=&a5 then do; E&a5.&var = &var; output casuser.train5; end;
drop engine X1 - X24;
run;

data casuser.mwpca_train;
merge  casuser.train1 casuser.train2 casuser.train3 casuser.train4 casuser.train5;
by cycle;
run;

proc mwpca data=casuser.mwpca_train windowsize=10 stepsize=2;
id cycle;
input E&a1.&var E&a2.&var E&a3.&var E&a4.&var E&a5.&var;
output out=casuser.windowpcs npc=1;
run;

proc sgplot data =casuser.windowpcs;
series x= window_id y= E&a1.&var /legendlabel = "Engine &a1 - &var" lineattrs = (thickness = 1);
series x= window_id y= E&a2.&var /legendlabel = "Engine &a2 - &var" lineattrs = (thickness = 1);
series x= window_id y= E&a3.&var /legendlabel = "Engine &a3 - &var" lineattrs = (thickness = 1);
series x= window_id y= E&a4.&var /legendlabel = "Engine &a4 - &var" lineattrs = (thickness = 1);
series x= window_id y= E&a5.&var /legendlabel = "Engine &a5 - &var" lineattrs = (thickness = 1);
title H=14pt "Anomaly Detection using Moving Windows PCA";
yaxis label="Device ID Energy Use";
xaxis label="Time";
run;
