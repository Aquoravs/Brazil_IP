# Scalar 2SLS (muni×year, coalition)

                                IV:Mayor     IV:M+G IV:M+G+b..
Dependent Var.:               log_gdp_pc log_gdp_pc log_gdp_pc
                                                              
delta_hhi                          3.909    -2.357   -2.412   
                                 (22.82)    (2.275)  (2.315)  
bndes_pc                                              1.22e-7 
                                                     (1.01e-6)
Fixed-Effects:                ---------- ---------- ----------
muni_id                              Yes        Yes        Yes
year                                 Yes        Yes        Yes
_____________________________ __________ __________ __________
S.E.: Clustered               by: muni.. by: muni.. by: muni..
Observations                      83,446     83,446     83,446
R2                               0.94669    0.94670    0.94670
F-test (1st stage), delta_hhi    0.01465    0.25196    0.25282
Sargan                                --    0.10414    0.07616
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
