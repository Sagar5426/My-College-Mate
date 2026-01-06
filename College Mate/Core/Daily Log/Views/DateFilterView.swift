//
//  DateFilterView.swift
//  College Mate
//
//  Created by Sagar Jangra on 22/08/2025.
//


import SwiftUI

struct DateFilterView: View {
    @State var start: Date
    
    var onSubmit: (Date) -> ()
    var onClose: () -> ()
    
    @State private var hasAppeared = false
    
    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let earliestDate = Calendar.current.date(byAdding: .year, value: -1, to: today) ?? today
        return earliestDate...today
    }
    
    var body: some View {
        VStack(spacing: 15) {
            DatePicker("Select Date", selection: $start, in: dateRange, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .opacity(hasAppeared ? 1 : 0)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeIn(duration: 0.2)) {
                            hasAppeared = true
                        }
                    }
                }
            
            HStack(spacing: 15) {
                Button("Cancel") {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 5))
                .tint(.red)
                
                Button("Done") {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onSubmit(start)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 5))
            }
            .padding(.top, 10)
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(.bar, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 30)
        .frame(maxWidth: 540)
    }
}

#Preview {
    DateFilterView(
        start: Date(),
        onSubmit: { start in
            print("Date submitted: \(start)")
        },
        onClose: {
            print("Date filter view closed")
        }
    )
}
