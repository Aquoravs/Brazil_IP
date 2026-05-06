# First Stage — Robustness (sector×year FE, coalition)

                                               M+G               M+P
Dependent Var.:                        delta_s_mjt       delta_s_mjt
                                                                    
Z_mayor_coalition_cycle_specific           0.0012           0.0034  
                                          (0.0046)         (0.0035) 
Z_gov_coalition_cycle_specific            -0.0017                   
                                          (0.0068)                  
Z_pres_coalition_cycle_specific                             0.0137**
                                                           (0.0043) 
Fixed-Effects:                         -----------       -----------
muni_id-sector_group                           Yes               Yes
sector_group-year                              Yes               Yes
________________________________       ___________       ___________
S.E.: Clustered                  by: muni. & sect. by: muni. & sect.
Observations                               700,650           700,650
R2                                         0.01262           0.01262

                                             M+G+P
Dependent Var.:                        delta_s_mjt
                                                  
Z_mayor_coalition_cycle_specific          0.0033  
                                         (0.0048) 
Z_gov_coalition_cycle_specific           -0.0005  
                                         (0.0070) 
Z_pres_coalition_cycle_specific           0.0137**
                                         (0.0045) 
Fixed-Effects:                         -----------
muni_id-sector_group                           Yes
sector_group-year                              Yes
________________________________       ___________
S.E.: Clustered                  by: muni. & sect.
Observations                               700,650
R2                                         0.01262
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
