*make format for gpa; 
proc format;
	invalue GPA
	"A" = 4.0 
	"A-" = 3.7
	"B+" = 3.4
	"B" = 3.0
	"B-" = 2.7
	"C+" = 2.4
	"C" = 2.0
	"C-" = 1.7
	"D+" = 1.4
	"D" = 1.0
	"D-"=.7
	"E"=0
	"UW"=0
	"WE"=0
	"IE"=0
	"P"=.
	"W"=.
	"T"=.
	"NS"=.
	"I"=.
	;
%macro drive(dir,ext);                                                                                                                  
  %local filrf rc did memcnt name i;                                                                                                    
                                                                                                                                        
  /* Assigns a fileref to the directory and opens the directory */                                                           
  %let rc=%sysfunc(filename(filrf,"&dir"));                                                                                               
  %let did=%sysfunc(dopen(&filrf));                                                                                                     
                                                                                                                                        
  /* Make sure directory can be open */                                                                                                 
  %if &did eq 0 %then %do;                                                                                                              
   %put Directory &dir cannot be open or does not exist;                                                                                
   %return;                                                                                                                             
  %end;                                                                                                                                 
                                                                                                                                        
   /* Loops through entire directory */                                                                                                 
   %do i = 1 %to %sysfunc(dnum(&did));                                                                                                  
                                                                                                                                        
     /* Retrieve name of each file */                                                                                                   
     %let name=%qsysfunc(dread(&did,&i));                                                                                               
                                                                                                                                        
     /* Checks to see if the extension matches the parameter value */                                                                   
     /* If condition is true print the full name to the log        */                                                                   
      %if %qupcase(%qscan(&name,-1,.)) = %upcase(&ext) %then %do;                                                                       
        %put &dir/&name; 
        data final MaStat;
			length Course $ 10;
			infile "&dir/&name" delimiter="@";
			input ID $ Date Course $ Credits Grade $;
			Date= substrn(Date,2,2)||substrn(Date,1,1);
			GPAgrade=input(Grade,GPA.);
			if Grade in ("P","T","I","NS") then creditweight=0;
			else creditweight= credits;
			if substr(Course,1,4) in ("MATH", "STAT") then output MaStat;
			output final;
		run;
      %end;                                                                                                                             
     proc append base=allfinal data=final;
     run;
     proc append base=stem data=mastat;
     run;
   %end;                                                                                                                                
                                                                                                                                        
  /* Closes the directory and clear the fileref */                                                                                      
  %let rc=%sysfunc(dclose(&did));                                                                                                       
  %let rc=%sysfunc(filename(filrf));                                                                                                    
                                                                                                                                        
%mend drive;                                                                                                                            
proc sql;
	reset noprint;
	drop table allfinal;
	drop table stem;
	quit;

/* First parameter is the directory of where your files are stored. */                                                                  
/* Second parameter is the extension you are looking for.           */                                                                  
%drive(/folders/myfolders/sasuser.v94/Stat 224/Final,txt)     
*sort to make data set of repeats;
proc sort data=stem out=random;
by ID Course;
run;
proc sort data=allfinal out=use;
by ID Course;
run;
*make number of repeat classes data set;

data repeats; 
	set use;
	by ID Course;
	if last.Course then repeats=0;
	else repeats=1;
run;
*make number of math and stat repeats data set;
data srepeats; 
	set random;
	by ID Course;
	if last.Course then repeats=0;
	else repeats=1;
run;


proc sql;
	create table reps as
	select ID,
	sum(repeats) as numreps
	from repeats
	group by ID;
quit;

proc sql;
	create table stemreps as
	select ID,
	sum(repeats) as stnumreps
	from srepeats
	group by ID;
quit;

*make semester GPA table;
proc sql;
	create table semesterGPA as
	select ID, Date,
	sum(GPAgrade*Credits) as weight,
	sum(Credits) as semesterCredits,
	sum(GPAgrade*Credits)/sum(Credits) as termGPA,
	sum(Creditweight) as gradedSemesterCreds 
	from allfinal
	group by ID, Date 
	order by ID, Date;
quit;
*create data set for class status;
data class_semester class_stand;
	length class $10;
	set semesterGPA;
	by ID Date;
	retain totalCredits;
	if first.ID then
	totalCredits=0;
	totalCredits=sum(totalCredits,semesterCredits);
	select;    
	when (totalCredits=<30) Class="Freshman";   
	when (totalCredits=<60) Class="Sophomore";    
	when (totalCredits=<90) Class="Junior";    
	otherwise class="Senior"; 
end;
if last.ID then output class_stand; 
output class_semester;
run;

*calculate weight and GPA along with class-table 1 for report 1;
proc sql;
	create table cuweight as 
	select distinct semesterGPA.ID, semesterGPA.date, semesterGPA.semesterCredits, semesterGPA.gradedSemesterCreds, 
	divide(sum(semesterGPA.weight),sum(semesterGPA.semesterCredits)) as finalGPA, semesterGPA.termGPA, class_semester.class
	from semesterGPA join class_semester on semesterGPA.ID=class_semester.ID and 
	semesterGPA.date=class_semester.date
	group by semesterGPA.ID, semesterGPA.date 
	order by semesterGPA.ID, semesterGPA.date;
quit;


*make table for overallGPA with number of graded courses;
proc sql;
	create table overallGPA as
	select distinct ID, sum(Credits) as Credits, sum(Creditweight) as gradedCreds, sum(GPAgrade*Credits)/sum(Credits) as overallGPA,
		sum(case when Grade in ("A","A-","A+") then 1 else 0 end) as numA,
		sum(case when Grade in ("B","B-","B+") then 1 else 0 end) as numB,
		sum(case when Grade in ("C","C-","C+") then 1 else 0 end) as numC,
		sum(case when Grade in ("D","D-","D+") then 1 else 0 end) as numD,
		sum(case when Grade in ("E","UW","WE","IE") then 1 else 0 end) as numE,
		sum(case when Grade in ("W") then 1 else 0 end) as numW
	from allfinal
	group by ID
	order by ID 
	;
quit;

*merge datasets for report 1 part b;
data resultsb (drop=weight semesterCredits termGPA);
	merge reps overallGPA class_stand;
	by ID;
run;

*for math and stat classes;
proc sql;
	create table ssemesterGPA as
	select ID, Date,
	sum(GPAgrade*Credits) as sweight,
	sum(Credits) as semestersCredits,
	sum(GPAgrade*Credits)/sum(Credits) as termsGPA,
	sum(Creditweight) as gradedsSemesterCreds 
	from stem
	group by ID, Date 
	order by ID, Date;
quit;
*cummulative stat-math gpa;
proc sql;
	create table stemcuweight as 
	select distinct ssemesterGPA.ID, ssemesterGPA.date, ssemesterGPA.semestersCredits, ssemesterGPA.gradedsSemesterCreds, 
	divide(sum(ssemesterGPA.sweight),sum(ssemesterGPA.semestersCredits)) as finalGPA, class_semester.class
	from ssemesterGPA join class_semester on ssemesterGPA.ID=class_semester.ID and 
	ssemesterGPA.date=class_semester.date
	group by ssemesterGPA.ID, ssemesterGPA.date 
	order by ssemesterGPA.ID, ssemesterGPA.date;
quit;

*make table for SoverallGPA with number of graded courses;
proc sql;
	create table SoverallGPA as
	select ID, sum(GPAgrade*Credits)/sum(Credits) as stemoverallGPA, 
	sum(Creditweight) as sgradedCreds, sum(Credits) as Credits, 
		sum(case when Grade in ("A","A-","A+") then 1 else 0 end) as numA,
		sum(case when Grade in ("B","B-","B+") then 1 else 0 end) as numB,
		sum(case when Grade in ("C","C-","C+") then 1 else 0 end) as numC,
		sum(case when Grade in ("D","D-","D+") then 1 else 0 end) as numD,
		sum(case when Grade in ("E","UW","WE","IE") then 1 else 0 end) as numE,
		sum(case when Grade in ("W") then 1 else 0 end) as numW
	from stem
	group by ID
	order by ID 
	;
quit;
*combine to make stem overall w/# of reps and # of A's etc. data set;
data stemresults;
	merge SoverallGPA stemreps;
	by ID;
run;
*for report 3- sort the data;
proc sort data=resultsb out=percent;
by descending overallGPA;
run;
* get top 10% overall for Juniors or Seniors;
%macro top10pct(lib=WORK,dataset=,whr=,sortvar=);
data top10;
set &lib..&dataset.(where=(&whr.));
run;
proc sort data=top10;
by descending &sortvar;
run;
proc sql noprint;
	select distinct max(ceil(0.1*nlobs)) into :_nobs 
	from dictionary.tables
	where upcase(libname)=upcase("&lib.") and upcase(memname)="TOP10";
quit;

data &lib..&dataset._10;
set &lib..top10(obs=&_nobs.);
run;
%mend top10pct;
%top10pct(lib=WORK,dataset=percent,whr=%str(Class in("Junior","Senior")),sortvar=overallGPA)


*for report 4- sort the data;
proc sort data=stemresults out=stempercent;
by descending stemoverallGPA;
run;

%top10pct(lib=WORK,dataset=stempercent,whr=%str(sgradedCreds >= 20),sortvar=stemoverallGPA)


ods html body="/folders/myfolders/sasuser.v94/Stat 224/Final.pdf";
title "Report 1A";
proc report data=cuweight;
columns ID termGPA finalGPA gradedSemesterCreds Class;
define ID / display "Student ID";
define termGPA / display "GPA" format=4.2;
define finalGPA / display "Cumulative GPA";
define gradedSemesterCreds / display "Credit Hours Earned";
define Class / display "Class";
run;
title "Report 1B";
proc report data=resultsb;
	columns ID overallGPA Credits gradedCreds numreps numA numB numC numD numE numW;
	define ID / display "Student ID";
	define overallGPA / display "GPA" format=4.2;
	define Credits / display "Credit Hours Earned";
	define gradedCreds / display "Graded Credit Hours Earned";
	define numreps / display "Repeats";
	define numA / display "A's";
	define numB / display "B's";
	define numC / display "C's";
	define numD / display "D's";
	define numE / display "E's";
	define numW / display "W's";
run;
title "Report 2A";
proc report data=resultsb; 
	columns ID overallGPA Credits gradedCreds numreps numA numB numC numD numE numW;
	define ID / display "Student ID";
	define overallGPA / display "GPA" format=4.2;
	define Credits / display "Credit Hours Earned";
	define gradedCreds / display "Graded Credit Hours Earned";
	define numreps / display "Repeats";
	define numA / display "A's";
	define numB / display "B's";
	define numC / display "C's";
	define numD / display "D's";
	define numE / display "E's";
	define numW / display "W's";
run;
title "Report 2B";
proc report data=stemresults; 
columns ID stemoverallGPA Credits sgradedCreds stnumreps numA numB numC numD numE numW;
	define ID / display "Student ID";
	define stemoverallGPA / display "GPA" format=4.2;
	define sgradedCreds / display "Graded Credit Hours Earned";
	define stnumreps / display "Repeats";
	define numA / display "A's";
	define numB / display "B's";
	define numC / display "C's";
	define numD / display "D's";
	define numE / display "E's";
	define numW / display "W's";
run;
title "Report 3";
proc report data=percent_10;
	columns ID gradedCreds overallGPA Class;
	define ID / display "Student ID";
	define gradedCreds / display "Graded Credit Hours";
	define overallGPA / display "GPA" format=4.2;
	define Class / display "Class";
run;
title "Report 4";
proc report data=stempercent_10;
	columns ID stemoverallGPA sgradedCreds;
	define ID / display "Student ID";
	define stemoverallGPA / display "Stem GPA" format=4.2;
	define sgradedCreds / display "Graded Stem Credits";
ods html close;