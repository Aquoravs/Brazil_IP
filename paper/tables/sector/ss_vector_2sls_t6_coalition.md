# Vector 2SLS: log(GDP_pc) ~ delta_s_j (muni×year, coalition)

                               Vec:Mayor    Vec:M+G Vec:M+G+bn..
Dependent Var.:               log_gdp_pc log_gdp_pc   log_gdp_pc
                                                                
delta_s_A                         0.5621   -0.3326      -0.3271 
                                 (2.828)   (0.5511)     (0.5462)
delta_s_B                         3.846     0.6804       0.6761 
                                (11.53)    (0.9731)     (0.9675)
delta_s_C                         1.089    -0.5076      -0.5245 
                                 (4.686)   (0.8603)     (0.8604)
delta_s_D                        -8.206     5.486*       5.417* 
                                (20.65)    (3.109)      (3.108) 
delta_s_E                       -12.10     -0.9409      -0.9578 
                                (21.66)    (3.136)      (3.129) 
delta_s_F                         3.122     0.6023       0.5970 
                                 (6.094)   (1.563)      (1.549) 
delta_s_H                        -1.057     0.6470       0.6435 
                                 (3.981)   (0.8686)     (0.8668)
delta_s_I                        12.58      2.353        2.340  
                                (25.77)    (4.387)      (4.382) 
delta_s_J                         2.530    -3.407*      -3.404* 
                                 (9.576)   (1.949)      (1.948) 
delta_s_K                        -2.493     0.3921       0.4113 
                                (11.16)    (2.092)      (2.082) 
delta_s_L                        27.52     -9.495       -9.341  
                                (79.37)   (10.69)      (10.65)  
delta_s_M                        -8.765     1.580        1.853  
                                (23.15)    (5.225)      (5.158) 
delta_s_N                        13.25      1.192        1.163  
                                (18.82)    (2.476)      (2.465) 
delta_s_P                        20.64     -3.913       -3.844  
                                (62.49)   (12.61)      (12.58)  
delta_s_Q                         3.479    -5.851       -5.792  
                                (35.75)    (9.409)      (9.383) 
delta_s_R                        -6.753    -7.224       -7.163  
                                (20.67)    (4.856)      (4.853) 
delta_s_S                        -1.871     1.771        1.729  
                                (15.79)    (4.051)      (4.057) 
bndes_pc                                                -5.05e-8
                                                    (1e-6)      
Fixed-Effects:                ---------- ---------- ------------
muni_id                              Yes        Yes          Yes
year                                 Yes        Yes          Yes
_____________________________ __________ __________ ____________
S.E.: Clustered               by: muni.. by: muni..  by: muni_id
Observations                      89,008     89,008       89,008
R2                               0.94548    0.94551      0.94551
F-test (1st stage), delta_s_A    0.90669    0.92585      0.92640
F-test (1st stage), delta_s_B    0.25415    0.75200      0.75139
F-test (1st stage), delta_s_C    0.20934    0.23005      0.22632
F-test (1st stage), delta_s_D    0.39213    0.30541      0.29453
F-test (1st stage), delta_s_E    0.17538    0.18459      0.18464
F-test (1st stage), delta_s_F    0.48348    0.35162      0.35153
F-test (1st stage), delta_s_H    0.36390    0.31034      0.30575
F-test (1st stage), delta_s_I    0.61732    0.36809      0.36807
F-test (1st stage), delta_s_J    0.31902    0.24361      0.24335
F-test (1st stage), delta_s_K    0.45950    0.51767      0.51769
F-test (1st stage), delta_s_L    0.06602    0.13973      0.13970
F-test (1st stage), delta_s_M    0.12966    0.12587      0.12851
F-test (1st stage), delta_s_N    0.36488    0.30371      0.30425
F-test (1st stage), delta_s_O    0.00472    0.00419      0.00419
F-test (1st stage), delta_s_P    0.05538    0.04708      0.04709
F-test (1st stage), delta_s_Q    0.20512    0.15663      0.15663
F-test (1st stage), delta_s_R    0.37288    0.34848      0.34844
F-test (1st stage), delta_s_S    0.87860    0.63151      0.63150
Sargan                                --     4.8428       4.9311
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
