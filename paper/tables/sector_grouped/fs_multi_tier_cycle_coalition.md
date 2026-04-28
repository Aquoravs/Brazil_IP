# First Stage — Multiple Instruments (cycle-specific, muni×year FE, coalition)

                                               M+G               M+P
Dependent Var.:                        delta_s_mjt       delta_s_mjt
                                                                    
Z_mayor_coalition_cycle_specific           0.0171            0.0148 
                                          (0.0097)          (0.0086)
Z_gov_coalition_cycle_specific             0.0040                   
                                          (0.0083)                  
Z_pres_coalition_cycle_specific                             -0.0096 
                                                            (0.0159)
Fixed-Effects:                         -----------       -----------
muni_id-sector_group                           Yes               Yes
muni_id-year                                   Yes               Yes
________________________________       ___________       ___________
S.E.: Clustered                  by: muni. & sect. by: muni. & sect.
Observations                               700,650           700,650
R2                                         0.06216           0.06216

                                             M+G+P
Dependent Var.:                        delta_s_mjt
                                                  
Z_mayor_coalition_cycle_specific           0.0155*
                                          (0.0079)
Z_gov_coalition_cycle_specific             0.0030 
                                          (0.0093)
Z_pres_coalition_cycle_specific           -0.0093 
                                          (0.0164)
Fixed-Effects:                         -----------
muni_id-sector_group                           Yes
muni_id-year                                   Yes
________________________________       ___________
S.E.: Clustered                  by: muni. & sect.
Observations                               700,650
R2                                         0.06216
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
