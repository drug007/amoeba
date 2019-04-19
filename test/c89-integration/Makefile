all : amoeba_test
		

clean : 
		rm test.gcda test.gcno amoebalib.o amoeba_test a.out amoebad.o

# amoebalib.o : amoeba.h
# 		gcc -shared -O2 -DAM_IMPLEMENTATION -xc -fPIC -o amoebalib.o amoeba.h

amoeba_test : test.c amoeba.d amoeba.h
		dmd -betterC -c amoeba.d -ofamoebad.o
		gcc -ggdb -Wall -fprofile-arcs -ftest-coverage -O0 -Wextra -pedantic -std=c89 -o amoeba_test amoebad.o test.c

# amoebad.o : amoeba.d
# 		rdmd -c amoeba.d -o amoebad.o

test : amoeba_test
		./amoeba_test

