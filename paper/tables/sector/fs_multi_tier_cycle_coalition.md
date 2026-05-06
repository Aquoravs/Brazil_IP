# First Stage — Multiple Instruments (cycle-specific, muni×year FE, coalition)

                                               M+G               M+P
Dependent Var.:                        delta_s_mjt       delta_s_mjt
                                                                    
Z_mayor_coalition_cycle_specific         0.0287***         0.0251***
                                        (0.0069)          (0.0065)  
Z_gov_coalition_cycle_specific           0.0024                     
                                        (0.0084)                    
Z_pres_coalition_cycle_specific                           -0.0184   
                                                          (0.0141)  
Fixed-Effects:                         -----------       -----------
muni_id-cnae_section                           Yes               Yes
muni_id-year                                   Yes               Yes
________________________________       ___________       ___________
S.E.: Clustered                  by: muni. & cnae. by: muni. & cnae.
Observations                             1,372,575         1,372,575
R2                                         0.03691           0.03691

                                             M+G+P
Dependent Var.:                        delta_s_mjt
                                                  
Z_mayor_coalition_cycle_specific         0.0252***
                                        (0.0054)  
Z_gov_coalition_cycle_specific           0.0006   
                                        (0.0097)  
Z_pres_coalition_cycle_specific         -0.0184   
                                        (0.0147)  
Fixed-Effects:                         -----------
muni_id-cnae_section                           Yes
muni_id-year                                   Yes
________________________________       ___________
S.E.: Clustered                  by: muni. & cnae.
Observations                             1,372,575
R2                                         0.03691
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
