%macro checkanswers(testform=);
*read in domain data sets-each question assigned to domain;
data Domain;
infile "/folders/myfolders/sasuser.v94/Stat 124/Domains Form&testform..csv" dlm="," dsd firstobs=2;
input ItemId Domain $ Domnum Question;
run;
/*read in key and student data sets
for each student have q and their answer and key data strip contains correct answers for questions*/
data key(keep=Qnumber answer) student(keep=ID Qnumber answer); 
	infile "/folders/myfolders/sasuser.v94/Stat 124/Form&testform..csv" delimiter="," dsd missover;
	input  ID $ (Q1-Q150) ($);
	array jared{150} $ Q1-Q150;
	do i=1 to 150;
	Qnumber=i;
	answer = jared{i};
	if strip(ID) = "%upcase(&testform.)%upcase(&testform.)%upcase(&testform.)%upcase(&testform.)KEY" then 
 	output key;
	else output student;
	end;
run;
*creates table that shows how many questions are in each domain;
proc sql;
	create table domcount as 
	select domnum, count (*) as domcount
	from domain 
	group by domnum
	;
quit;
*create table for each student for each of the questions they answered and sets domain for each question;
proc sql;
	create table random as 
	select ID as Student, key.answer as correct, Domain.Domnum as Domain, domcount,
		case when student.answer=key.answer then 1 else 0 end as score
	from student, key, Domain, domcount 
	where student.Qnumber=key.Qnumber and student.Qnumber=Domain.Question and 
		domain.domnum = domcount.domnum
	;
quit;
*one record for student and each domain and their percent in that doamin;
proc sql;
	create table dom&testform. as 
	select distinct Student, domain,domcount, sum(score) as total, divide(sum(score),avg(domcount)) as percent
	from random
	group by Student, Domain
	;
	quit;
*calculate overall score and percent for each student-creates one record per student ;	
proc sql;
	create table form&testform. as 
	select distinct Student, 9 as domain, sum(score) as total, divide(sum(score),150) as percent
	from random
	group by Student
	;
	quit;
*drops random table;	
proc sql;
	drop table random;
quit;
*merges form and domain data sets;
data together;
set dom&testform. form&testform.;
run;
* sort to get a record for each student for each domain including overall(ie 9);
proc sort data=together;
by Student Domain;
run;
*makes table with total for domain and overall as columns;
proc transpose data=together out=transtogethertotal prefix=total;
var total;
id domain;
by student;
run;
*makes table with percent for domain and overall as columns;
proc transpose data=together out=transtogetherpercent prefix=percent;
var percent;
id domain;
by student;
run;
*creates table that combines the transposed data into table for the transposed data we made;
data transtogether&testform.;
merge transtogethertotal(drop=_name_) transtogetherpercent(drop=_name_);
by student;
run;
%mend;
%checkanswers(testform=A)
%checkanswers(testform=B)
%checkanswers(testform=C)
%checkanswers(testform=D)
;
*combines together data sets into one;
data ttogether;
set transtogethera transtogetherb transtogetherc transtogetherd;
run;

data domains;
set doma domb domc domd;
run;

data forms;
set forma formb formc formd;
run;
*creates a counter for domain count;
proc sql;
	reset noprint;
	select count(distinct student)  
	into :stucount from forms
	;
	quit;
*creates domain/overall total and percents into table;	
proc sql;
	create table domaintot as
	select distinct domain, divide(sum(total),sum(domcount)) as percent
	from domains
	group by domain
	union 
	select 9 as domain, divide(sum(total),(&stucount.*150)) as percent
	from forms
	;
	quit;

*print out data in tables; 
ods pdf body="/folders/myfolders/sasuser.v94/Stat 224/Midterm.pdf";
title "Domain Scores and Percent";
proc report data=ttogether nowd
	style(header)={background=white};
	columns Student ('1' total1 percent1) ('2' total2 percent2) ('3' total3 percent3) 
	('4' total4 percent4) ('5' total5 percent5) ('Overall' total9 percent9);
	define total1 / display "Total Domain 1";
	define percent1 / display "Percent Domain 1" format=percent10.1;
	define total2 / display "Total Domain 2";
	define percent2 / display "Percent Domain 2" format=percent10.1;
	define total3 / display "Total Domain 3";
	define percent3 / display "Percent Domain 3" format=percent10.1;
	define total4 / display "Total Domain 4";
	define percent4 / display "Percent Domain 4" format=percent10.1;
	define total5 / display "Total Domain 5";
	define percent5 / display "Percent Domain 5" format=percent10.1;
	define total9 / display "Total Overall";
	define percent9 / display "Percent Overall" format=percent10.1;
run;
title "Scores By Domain";
proc report data=domaintot nowd;
	columns Domain percent;
	define Domain / display "Domain Name";
	define percent / display "Percent Correct" format=percent10.1;
run;

ods pdf close;