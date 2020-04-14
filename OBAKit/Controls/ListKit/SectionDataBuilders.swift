//
//  SectionDataBuilders.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 4/13/20.
//

import UIKit
import OBAKitCore
import IGListKit

protocol SectionDataBuilders: NSObjectProtocol {
    func sectionData(from situations: [Situation]) -> [MessageSectionData]
}

extension SectionDataBuilders where Self: AppContext {
    
    func sectionData(from situations: [Situation]) -> [MessageSectionData] {
        var sections = [MessageSectionData]()
        for serviceAlert in Set(situations).allObjects.sorted(by: { $0.createdAt > $1.createdAt }) {
            let formattedDate = application.formatters.shortDateTimeFormatter.string(from: serviceAlert.createdAt)
            let message = MessageSectionData(author: Strings.serviceAlert, date: formattedDate, subject: serviceAlert.summary.value, summary: serviceAlert.situationDescription.value) { [weak self] _ in
                guard let self = self else { return }
                let serviceAlertController = ServiceAlertViewController(serviceAlert: serviceAlert, application: self.application)
                self.application.viewRouter.navigate(to: serviceAlertController, from: self)
            }
            sections.append(message)
        }
        return sections
    }
}
